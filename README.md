# coroutines

Two coroutine flavours plus a hybrid backend for Zig 0.17.0, standard library only (no third-party dependencies).

| module | what a coroutine is | switch | memory per task | parallelism |
|---|---|---|---|---|
| `coroutines.state_machine` | a struct with a state field and `pub fn step(*T) Step` (`.yield` / `.done`) | a function return + call | `@sizeOf(T)`, caller-provided storage, 0 allocations | `runParallel`: N OS threads, lock-free chunked work queue |
| `coroutines.io` | a function run through `std.Io` (`Io.Group`, `Io.Queue`) | whatever the `Io` does (thread handoff for `std.Io.Threaded`) | one allocation per task in `std.Io.Threaded` (64 B measured) | the `Io` thread pool |
| `coroutines.hybrid` | `task(ctx, i) u64`, results summed | processes while `n <= threshold` (default 256), `Io` coroutines above | as processes / as `io` | worker processes (one per CPU) or the `Io` thread pool |

## Usage

```zig
const coro = @import("coroutines");

// 1. State machine
const Task = struct {
    left: u32,
    pub fn step(t: *Task) coro.state_machine.Step {
        t.left -= 1;
        return if (t.left == 0) .done else .yield;
    }
};
var tasks: [1000]Task = @splat(.{ .left = 10 });
_ = try coro.state_machine.runAll(Task, &tasks, null);           // one thread
try coro.state_machine.runParallel(Task, &tasks, .{ .threads = 4 }); // N threads

// 2. std.Io
var group: std.Io.Group = .init;
coro.io.spawnEach(io, &group, 10_000, myTask, ctx); // myTask(ctx, i) Io.Cancelable!void
try group.await(io); // or group.cancel(io)

var buf: [64]Msg = undefined;
var d: coro.io.Dispatcher(Msg, *Ctx, handler) = .init(io, ctx, &buf);
try d.start(4);       // 4 worker coroutines reading a bounded Io.Queue
try d.submit(msg);
try d.shutdown();     // close queue, drain, join  (d.cancel() for a hard stop)
```

Add to a project: `zig fetch --save git+https://github.com/pyrlyn/coroutines` and
`exe.root_module.addImport("coroutines", b.dependency("coroutines", .{}).module("coroutines"))`.

## Design

### `state_machine`

* A coroutine is a plain struct; its progress lives in its own fields, so a "switch"
  is just returning from `step` and the scheduler calling the next task's `step`.
  No stacks, no allocation, no syscalls.
* `runAll(T, tasks, cancel)` — round-robin on the calling thread. Finished tasks are
  swapped to the end of the slice, so each round touches only live tasks.
* `runParallel(T, tasks, opts)` — up to `max_threads` (64) workers including the caller.
  Work distribution is one atomic cursor (`fetchAdd` of `chunk` tasks); a worker runs
  its chunk to completion and claims the next one. Thread handles live on the caller's
  stack. All threads are joined before returning, also on cancellation.
* Cancellation: an optional `*const std.atomic.Value(bool)`, checked between rounds;
  the run returns `error.Canceled` after all workers have stopped.
* Limitation: a task that never yields blocks its worker; there is no preemption.

### `hybrid`

* `hybrid.run(io, gpa, n, ctx, task, .{ .threshold = 256, .processes = 0 })` runs
  `task(ctx, i)` for `i` in `0..n` and returns `.{ .sum, .mode, .children_peak_rss_bytes }`.
* `n <= threshold` → `.processes`: the current binary is re-executed `min(n, processes or CPU count)`
  times with `--coroutines-hybrid-worker lo hi`; each child prints its partial sum. Programs
  using it must call `hybrid.workerMain(io, args, ctx, task)` first thing in `main`.
* `n > threshold` → `.io`: one `Io.Group` task per index (same as `io.spawnEach`).
* Default 256 = the process count from which `io-group` beat processes on wall time on macOS
  in the sweep below. `hybrid.chooseMode(n, threshold)` is the pure decision function.

### `io`

* Built only on the `std.Io` interface, so the same code runs on `std.Io.Threaded`
  (thread pool, all OSes) or an evented `Io` where the standard library has one
  (`coroutines.io.evented_available`; experimental in 0.17 and not available on Windows,
  so tests use `std.Io.Threaded`).
* `spawnEach` spawns many small tasks into an `Io.Group`; `Group.await` /
  `Group.cancel` give completion and cancellation for the whole group.
* `Dispatcher(Msg, Ctx, handler)` — N worker coroutines (`Group.concurrent`) pulling
  from a bounded `Io.Queue(Msg)` and calling `handler(ctx, msg)`. `shutdown` closes
  the queue and waits until it is drained; `cancel` stops workers at their next
  cancellation point.

## Tests

`zig build test` — 11 unit tests plus the `hybrid-e2e` executable:

* state machine: 10k tasks round-robin with exact step count and results; 10k tasks on
  4 threads with ≥ 2 distinct threads observed; cancellation joins all workers.
* io: 10k tasks in an `Io.Group` with ≥ 2 distinct threads; a `Dispatcher` with 4 workers
  processing 10k messages and shutting down cleanly; `Group.cancel` stopping endless
  sleeping tasks; `Dispatcher.cancel` with blocked workers.
* hybrid: `chooseMode` below / exactly at / above the threshold; Io mode result. `tests/hybrid_main.zig`
  runs the real processes mode end to end for n = 0, 1, 255, 256 (processes), 257, 10,000 (Io),
  custom thresholds 99/100, and checks both modes return the identical sum for the same n.

## Benchmarks

`zig build bench` (always ReleaseFast) or `bench/run.sh` (suites: `switch`, `spawn`, `procs`, `sweep`; select with `SUITES=...`) to write one file per suite into
[`bench/results/`](bench/results) with machine, OS, CPU, Zig version and date.
Every variant runs in a fresh process (median of 5), so RSS, page faults and context
switches belong to that variant only. Workload: 10,000 tasks, each 4 slices of 256
xorshift64 rounds (the state-machine task yields between slices).

Variants:

* `sm-switch` — one state-machine task yielding 10M times (ns per `step`).
* `io-switch` — two `Io` tasks ping-ponging a value over two 1-slot `Io.Queue`s (ns per handoff).
* `sequential` — a plain loop, one thread.
* `procs-N` — this binary spawned N times (`bench worker a b`), each child doing 1/N of the tasks (`procs` suite: N = 2; `sweep` suite: N = 1, 2, 4, … 1024).
* `sm-1thread` / `sm-parallel` — `runAll` / `runParallel` with one thread per CPU.
* `io-group` — `spawnEach` + `Group.await` on `std.Io.Threaded`.

### Results (2026-10-31, Apple M3 Max)

macOS = native (16 logical CPUs). Linux = Ubuntu 26.04 in a Lima `vz` VM with 4 vCPUs and
4 GiB RAM on the same Mac. Full tables, including page faults, are in `bench/results/`
(`switch-*`, `spawn-*`, `procs-*`, `sweep-*`).

| variant | macOS ns/op | Linux ns/op | allocs/task | RSS MB total macOS | RSS MB total Linux | vol / invol ctx switches macOS | vol / invol ctx switches Linux |
|---|---:|---:|---:|---:|---:|---:|---:|
| sm-switch (per step) | 1.4 | 1.6 | 0 | 1.9 | 1.4 | 0 / 14 | 0 / 2 |
| io-switch (per handoff) | 1,884 | 10,252 | 0 (1 total) | 2.0 | 1.9 | 0 / 400,628 | 400,218 / 3 |
| sequential | 1,732 | 1,710 | 0 | 1.9 | 1.4 | 0 / 24 | 0 / 2 |
| procs-2 (2 worker processes) | 1,170 | 934 | 0 | 6.1 | 4.7 | 3 / 14 | 6 / 0 |
| sm-1thread | 1,665 | 1,548 | 1 for all tasks | 2.2 | 1.7 | 0 / 18 | 0 / 0 |
| sm-parallel | 155 | 420 | 1 for all tasks | 2.5 | 4.8 | 0 / 64 | 2 / 4 |
| io-group | 3,260 | 7,019 | 1 (64 B) | 2.8 | 2.9 | 0 / 10,230 | 8,602 / 1 |

ns/op is wall time divided by 10,000 tasks (or by steps / handoffs for the switch rows).
"RSS MB total" = parent peak RSS + the sum of every child's own peak RSS (`wait4` rusage per child).

### Process sweep

N worker processes split the same 10,000 tasks; N doubles from 1 up to 1024 or until the
projected RSS of the next N would exceed 50% of available RAM (macOS: 45.5 GB available,
Linux VM: 3.3 GB; neither cap was reached before N = 1024). Median of 3 runs.
"spawn" = time to spawn all N children.

| N / variant | macOS total ms | macOS spawn ms | macOS RSS MB | Linux total ms | Linux spawn ms | Linux RSS MB |
|---|---:|---:|---:|---:|---:|---:|
| procs-1 | 19.6 | 0.2 | 4.1 | 17.4 | 0.2 | 3.1 |
| procs-2 | 11.3 | 0.3 | 6.1 | 9.0 | 0.3 | 4.7 |
| procs-4 | 7.2 | 0.6 | 10.0 | 5.1 | 0.6 | 7.9 |
| procs-8 | 5.9 | 1.0 | 18.0 | 7.4 | 6.0 | 13.6 |
| procs-16 | 6.4 | 2.5 | 33.8 | 8.6 | 7.4 | 26.3 |
| procs-32 | 9.6 | 5.4 | 65.4 | 11.7 | 10.9 | 51.1 |
| procs-64 | 16.1 | 11.2 | 128.5 | 13.0 | 12.4 | 100.5 |
| procs-128 | 30.0 | 27.5 | 254.9 | 19.6 | 19.2 | 199.0 |
| procs-256 | 56.2 | 53.9 | 507.0 | 40.3 | 39.5 | 398.4 |
| procs-512 | 127.7 | 124.3 | 1,012.1 | 81.5 | 80.1 | 798.1 |
| procs-1024 | 645.9 | 313.4 | 2,022.5 | 182.7 | 180.0 | 1,582.3 |
| **sm-parallel** | **1.5** | – | **2.5** | **4.4** | – | 4.8 |
| **io-group** | 30.2 | – | 2.8 | 71.3 | – | **2.9** |

Where coroutines win (from the sweep table):

| | time | memory |
|---|---|---|
| sm-parallel vs N processes | every N on both OSes (best process run: N = 8 on macOS, 5.9 ms vs 1.5 ms; N = 4 on Linux, 5.1 ms vs 4.4 ms) | every N on macOS (2.5 MB < 4.1 MB at N = 1); N ≥ 4 on Linux (4.8 MB vs 3.1 / 4.7 / 7.9 MB at N = 1 / 2 / 4) |
| io-group vs N processes | N ≥ 256 on macOS (at N = 128 it is a tie, 30.2 vs 30.0 ms) and N ≥ 512 on Linux (71.3 vs 81.5 ms) | every N on both OSes (2.8 / 2.9 MB vs 4.1 / 3.1 MB at N = 1) |

### Analysis

All statements below are derived from the tables above; anything not measured is marked
*hypothesis*.

**Speed: `sm-parallel` wins everywhere.** 10k tasks took 1.5 ms on macOS (11× faster than
`sequential`) and 4.4 ms on Linux with 4 vCPUs (3.9×). It made one allocation for all tasks
and at most 64 context switches, so nearly all of its time is the work itself spread over
the cores.

**State machine vs `Io`.** A state-machine switch costs 1.4–1.6 ns with zero allocations and
zero context switches. An `Io` handoff on `std.Io.Threaded` cost 1.9 µs (macOS) and 10.3 µs
(Linux) — about 1,300× and 6,400× more — with one context switch per handoff (≈400k for 400k
handoffs; counted as involuntary on macOS, voluntary on Linux). For many small tasks
`io-group` was slower than one thread (3.3 vs 1.7 µs/task on macOS, 7.0 vs 1.7 on Linux): it
made exactly one allocation (64 B) per task and ~0.86–1 context switch per task (10.2k on
macOS, 8.6k on Linux for 10k tasks). So on this CPU-bound workload the measured costs of
`Io` are an allocation plus a kernel-level thread wake-up per task, which the state machine
does not pay. *Hypothesis, not measured:* `Io` coroutines pay off when tasks really wait on
I/O, and an evented `Io` would cut the per-switch cost (not benchmarked: experimental in 0.17).

**Processes vs coroutines.** More processes help only up to the core count, then process
creation dominates. Best process counts were N = 8 on macOS (5.9 ms) and N = 4 on Linux
(5.1 ms). From N = 16 on, spawn time is ≥ 38% of total and from N = 64 on ≥ 70% (macOS:
11.2 of 16.1 ms at N = 64, 313 of 646 ms at N = 1024; Linux: 12.4 of 13.0 ms at N = 64).
Spawning costs ~0.2–0.3 ms per process on macOS at N ≥ 128 (27.5 ms / 128 … 313 ms / 1024)
and ~0.15–0.18 ms on Linux. `sm-parallel` beat the best process count by 3.8× on macOS and
1.2× on Linux.

**Memory.** Each process carries its own baseline: the sum of children RSS grew linearly at
≈ 2.0 MB per process on macOS and ≈ 1.55 MB on Linux (2,020 MB / 1024 and 1,580 MB / 1024),
so 1024 processes used 2.0 GB / 1.6 GB for work that coroutines did in 2.5–4.8 MB. Both
coroutine variants stay in one process: `io-group` 2.8–2.9 MB, `sm-parallel` 2.5 MB on macOS
and 4.8 MB on Linux. On Linux `sm-parallel` had more minor page faults than `sm-1thread`
(417 vs 210). *Hypothesis:* the extra ~3 MB is touched worker-thread stacks (1 MiB each) and
per-thread libc state; on macOS the same variant used 2.5 MB.

**Not measured.** Cache misses: `perf` exists in the Lima VM but the virtualised CPU reports
`cache-misses` / `cache-references` as `<not supported>` (tried with `sudo -n`;
`perf_event_paranoid` left unchanged). Windows: tests and benchmark compile for
x86_64-windows but were not run; there the benchmark reports only peak working set and page
faults (no `getrusage`). macOS reports almost every switch as involuntary and Linux as
voluntary, so compare context-switch counts within one OS only. The Linux VM ran with 4 vCPUs,
so its parallel numbers are not comparable 1:1 with the 16-CPU macOS numbers.

## Hybrid backend

macOS only (Apple M3 Max, 16 CPUs), `SUITES=hybrid bench/run.sh` →
[`bench/results/hybrid-darwin-arm64.md`](bench/results/hybrid-darwin-arm64.md). Same task as above
(~1k xorshift rounds); N = number of tasks. processes = min(N, 16) worker processes.
**Bold** = the hybrid switched to Io (N > 256). CPU % = (user + sys CPU time of the variant
and its children) / wall time of the same interval; 100% = one core busy.

| variant | N | wall ms | RSS MB | CPU % | hybrid mode |
|---|---:|---:|---:|---:|---|
| variant | N | wall ms | RSS MB | CPU % | hybrid mode |
| state machine | 16 | 0.14 | 2.2 | 244 |  |
| Io | 16 | 0.18 | 2.7 | 335 |  |
| processes | 16 | 5.85 | 33.8 | 640 |  |
| hybrid | 16 | 5.56 | 33.1 | 643 | processes |
| state machine | 64 | 0.17 | 2.2 | 263 |  |
| Io | 64 | 0.34 | 2.4 | 304 |  |
| processes | 64 | 5.81 | 33.8 | 623 |  |
| hybrid | 64 | 5.43 | 33.1 | 645 | processes |
| state machine | 255 | 0.48 | 2.2 | 164 |  |
| Io | 255 | 1.08 | 2.8 | 363 |  |
| processes | 255 | 5.59 | 33.8 | 664 |  |
| hybrid | 255 | 5.50 | 33.1 | 624 | processes |
| state machine | 256 | 0.48 | 2.2 | 156 |  |
| Io | 256 | 1.05 | 2.7 | 351 |  |
| processes | 256 | 5.81 | 33.9 | 595 |  |
| hybrid | 256 | 5.54 | 33.1 | 616 | processes |
| state machine | 257 | 0.46 | 2.2 | 156 |  |
| Io | 257 | 1.12 | 2.6 | 327 |  |
| processes | 257 | 6.16 | 33.8 | 593 |  |
| hybrid | 257 | 0.96 | 2.7 | 342 | **Io (switched)** |
| state machine | 1024 | 0.50 | 2.3 | 405 |  |
| Io | 1024 | 3.67 | 2.7 | 328 |  |
| processes | 1024 | 6.04 | 33.8 | 618 |  |
| hybrid | 1024 | 3.98 | 2.7 | 319 | **Io (switched)** |
| state machine | 10000 | 1.85 | 2.5 | 1034 |  |
| Io | 10000 | 37.63 | 2.8 | 323 |  |
| processes | 10000 | 7.63 | 33.8 | 739 |  |
| hybrid | 10000 | 32.73 | 2.9 | 321 | **Io (switched)** |

Measured:

* The switch works as configured: at N = 255 and 256 the hybrid ran processes (≈ 5.5 ms,
  33.1 MB — the same as the processes variant); at N = 257 it ran Io (0.96 ms, 2.7 MB — the same
  as the Io variant). Above the threshold it tracks Io, below it tracks processes.
* By task count, Io beat processes on wall time at every N up to 1024 (0.18 vs 5.85 ms at N = 16,
  3.67 vs 6.04 ms at N = 1024) and lost at N = 10,000 (37.6 vs 7.6 ms). The processes variant
  costs ≈ 5–6 ms of fixed spawn overhead and ≈ 34 MB for 16 children; Io stays at ≈ 2.7 MB.
  So with this workload a threshold defined on task count would sit *below* 16 for time and
  processes would win again somewhere between 1,024 and 10,000 tasks — the default 256 came from
  the process-count sweep, where the axis was the number of processes, not tasks. The threshold
  is a parameter; pick it from this table for your task size.
* The state machine was fastest and smallest at every N (0.14–1.85 ms, 2.2–2.5 MB).
* CPU %: processes use 6–7 cores (593–739%); Io ≈ 3–3.6 cores (304–363%); the state machine
  1.6–4 cores up to N = 1024 and 10 cores at 10,000 (most of its short runs is thread start-up).
  *Hypothesis:* Io's ~3.3 cores reflect the thread hand-off cost seen in the switch benchmark.

## License

No license file yet (pyrlyn/jit, the reference repo, has none either).
