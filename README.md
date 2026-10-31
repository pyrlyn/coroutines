# coroutines

Two coroutine flavours for Zig 0.17.0, standard library only (no third-party dependencies).

| module | what a coroutine is | switch | memory per task | parallelism |
|---|---|---|---|---|
| `coroutines.state_machine` | a struct with a state field and `pub fn step(*T) Step` (`.yield` / `.done`) | a function return + call | `@sizeOf(T)`, caller-provided storage, 0 allocations | `runParallel`: N OS threads, lock-free chunked work queue |
| `coroutines.io` | a function run through `std.Io` (`Io.Group`, `Io.Queue`) | whatever the `Io` does (thread handoff for `std.Io.Threaded`) | one allocation per task in `std.Io.Threaded` (64 B measured) | the `Io` thread pool |

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

`zig build test` — 9 tests:

* state machine: 10k tasks round-robin with exact step count and results; 10k tasks on
  4 threads with ≥ 2 distinct threads observed; cancellation joins all workers.
* io: 10k tasks in an `Io.Group` with ≥ 2 distinct threads; a `Dispatcher` with 4 workers
  processing 10k messages and shutting down cleanly; `Group.cancel` stopping endless
  sleeping tasks; `Dispatcher.cancel` with blocked workers.

## Benchmarks

`zig build bench` (always ReleaseFast) or `bench/run.sh` to write one file per suite into
[`bench/results/`](bench/results) with machine, OS, CPU, Zig version and date.
Every variant runs in a fresh process (median of 5), so RSS, page faults and context
switches belong to that variant only. Workload: 10,000 tasks, each 4 slices of 256
xorshift64 rounds (the state-machine task yields between slices).

Variants:

* `sm-switch` — one state-machine task yielding 10M times (ns per `step`).
* `io-switch` — two `Io` tasks ping-ponging a value over two 1-slot `Io.Queue`s (ns per handoff).
* `sequential` — a plain loop, one thread.
* `procs2` — this binary spawned twice (`bench worker a b`), each doing half the tasks.
* `sm-1thread` / `sm-parallel` — `runAll` / `runParallel` with one thread per CPU.
* `io-group` — `spawnEach` + `Group.await` on `std.Io.Threaded`.

### Results (2026-10-31, Apple M3 Max)

macOS = native (16 logical CPUs). Linux = Ubuntu 26.04 in a Lima `vz` VM with 8 vCPUs on
the same Mac. Full tables, including page faults, are in `bench/results/`.

| variant | macOS ns/op | Linux ns/op | allocs/task | peak RSS MB macOS | peak RSS MB Linux | vol / invol ctx switches macOS | vol / invol ctx switches Linux |
|---|---:|---:|---:|---:|---:|---:|---:|
| sm-switch (per step) | 1.4 | 1.6 | 0 | 1.9 | 1.4 | 0 / 16 | 0 / 0 |
| io-switch (per handoff) | 1,762 | 10,123 | 0 (1 total) | 2.0 | 2.0 | 0 / 400,688 | 400,130 / 1 |
| sequential | 1,637 | 1,672 | 0 | 1.9 | 1.4 | 0 / 13 | 0 / 0 |
| procs2 (2 worker processes) | 1,088 | 906 | 0 | 6.0 total | 4.7 total | 3 / 13 | 6 / 0 |
| sm-1thread | 1,508 | 1,530 | 1 for all tasks | 2.2 | 1.7 | 0 / 13 | 0 / 0 |
| sm-parallel | 145 | 257 | 1 for all tasks | 2.5 | 5.9 | 0 / 42 | 2 / 0 |
| io-group | 3,004 | 8,280 | 1 (64 B) | 2.7 | 4.3 | 0 / 10,230 | 11,909 / 1 |

ns/op is wall time divided by 10,000 tasks (or by steps / handoffs for the switch rows),
from the `procs` and `switch` suites. `procs2` process spawn alone took 264 µs (macOS) and
322 µs (Linux) for both children. "RSS total" for `procs2` = parent + 2 × the largest
child (`getrusage(RUSAGE_CHILDREN)` reports the maximum child, not a sum).

### Analysis

**Speed: `sm-parallel` wins everywhere.** It finished the 10k-task workload in 1.45 ms on
macOS (11× faster than `sequential`) and 2.6 ms on Linux (6.5×, with 8 vCPUs). It made one
allocation for all tasks and almost no context switches (≤ 54 involuntary), so nearly all
of its time is the work itself spread over the cores.

**State machine vs `Io`.** A state-machine switch costs 1.4–1.6 ns with zero allocations and
zero context switches. An `Io` handoff on `std.Io.Threaded` cost 1.8 µs (macOS) and 10 µs
(Linux), i.e. ~1,000–6,000× more, and it shows one context switch per handoff (400k for 400k
handoffs, involuntary on macOS, voluntary on Linux). That is the measured reason: under
`std.Io.Threaded` a blocked task parks its OS thread, and the wake-up goes through the
kernel. For many small tasks `io-group` was the slowest variant, even slower than one
thread (3.0 µs/task vs 1.6 µs on macOS, 8.3 vs 1.7 on Linux): it made exactly one
allocation (64 B) and about one context switch per task (10.2k on macOS, 11.9k on Linux for
10k tasks). The state machine wins whenever the task is CPU-bound and short.
*Hypothesis, not measured here:* `Io` coroutines become competitive when tasks actually wait
on I/O, where blocking an OS thread is the point, and with an evented `Io` (not
benchmarked: experimental in 0.17).

**Processes vs coroutines.** Two worker processes were 1.5–1.8× faster than `sequential`,
but `sm-parallel` was 7.5× (macOS) and 3.5× (Linux) faster than `procs2`. Spawning the two
children alone took 0.26–0.32 ms, i.e. 18% / 13% of `sm-parallel`'s whole run time on macOS /
Linux, and `procs2` uses only 2 cores. Memory: `procs2` used 6.0 MB / 4.7 MB total RSS
vs 2.5 MB / 5.9 MB for `sm-parallel` and 1.7–2.2 MB for single-threaded variants; each
extra process pays its own ~1.5–2 MB baseline.

**Memory.** Single-threaded variants are smallest (1.4–2.2 MB). On Linux, `sm-parallel` peaked
at 5.9 MB in the `procs` suite and 11.9 MB in the `spawn` suite, with more minor page faults
than `sm-1thread` (see result files). *Hypothesis:* the difference is touched thread stacks
(7 workers × up to 1 MiB) and per-thread libc state; the run-to-run spread suggests it depends
on how deep each stack got. On macOS the same variant stayed at 2.4–2.5 MB.

**Not measured.** Cache misses: `perf` exists in the Lima VM but the virtualised CPU reports
`cache-misses` / `cache-references` as `<not supported>` (with `sudo -n`; `perf_event_paranoid`
was left unchanged). Windows: tests and benchmark compile for x86_64-windows; benchmarks were
not run there, and Windows has no `getrusage`, so the benchmark reports only peak working set
and page faults there. macOS reports almost every switch as involuntary, Linux as voluntary;
compare context-switch counts within one OS only.

## License

No license file yet (pyrlyn/jit, the reference repo, has none either).
