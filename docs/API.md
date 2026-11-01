# API reference

Zig 0.17.0, standard library only. Import: `const coro = @import("coroutines");`

Public surface (everything else is internal):

| name | kind | summary |
|---|---|---|
| `coro.state_machine.Step` | enum | `.yield` / `.done`, returned by a coroutine's `step` |
| `coro.state_machine.Error` | error set | `error.Canceled` |
| `coro.state_machine.runAll` | fn | run tasks round-robin on the calling thread |
| `coro.state_machine.runParallel` | fn | run tasks on N OS threads |
| `coro.state_machine.ParallelOptions` | struct | `threads`, `chunk`, `cancel`, `stack_size`, `caller_works` |
| `coro.state_machine.currentWorker` | fn | index of the `runParallel` worker running on this thread |
| `coro.state_machine.max_threads` | const | 64, upper bound for `threads` |
| `coro.state_machine.worker_stack_size` | const | 1 MiB, default stack per worker thread |
| `coro.io.spawnEach` | fn | spawn `n` tasks into a `std.Io.Group` |
| `coro.io.Dispatcher` | fn → type | worker pool over a bounded `std.Io.Queue` |
| `coro.io.evented_available` | const bool | evented `std.Io` exists on this target |

## `state_machine`

A coroutine is any struct `T` with

```zig
pub fn step(self: *T) coro.state_machine.Step
```

Its progress lives in its own fields (typically a `state` enum). `step` does a bit of
work and returns `.yield` (call me again) or `.done`. A switch is a plain return + call:
no stack, no allocation, no syscall. A `step` that never returns blocks its thread; there is
no preemption.

### `runAll(comptime T: type, tasks: []T, cancel: ?*const std.atomic.Value(bool)) Error!u64`

Runs all tasks round-robin on the calling thread until every one returned `.done`.

* `tasks` — caller-owned storage. **Permuted in place**: finished tasks are swapped to the
  end, so identify tasks by a field, not by index.
* `cancel` — optional flag checked once per round. `null` = run to completion.
* Returns the number of `step` calls, or `error.Canceled` (unfinished tasks are then at the
  front of the slice).

```zig
const Countdown = struct {
    left: u32,
    pub fn step(c: *Countdown) coro.state_machine.Step {
        c.left -= 1;
        return if (c.left == 0) .done else .yield;
    }
};
var tasks: [3]Countdown = .{ .{ .left = 1 }, .{ .left = 2 }, .{ .left = 3 } };
const steps = try coro.state_machine.runAll(Countdown, &tasks, null); // 6
```

### `runParallel(comptime T: type, tasks: []T, opts: ParallelOptions) Error!void`

Runs tasks on up to `opts.threads` threads, the calling thread included unless
`opts.caller_works` is false. Workers claim
chunks of `opts.chunk` tasks from one atomic cursor and run each chunk with `runAll`. Every
task is stepped by exactly one thread, so its own fields need no locking; shared state does.
All threads are joined before returning, also on cancellation. If the OS refuses a thread,
the run continues with fewer workers.

`ParallelOptions`:

| field | default | meaning |
|---|---|---|
| `threads` | `0` | total workers incl. caller; `0` = CPU count; capped at `max_threads` |
| `chunk` | `64` | tasks claimed at once; larger = less contention, worse balance |
| `cancel` | `null` | `?*const std.atomic.Value(bool)`; set to `true` to stop |
| `stack_size` | `worker_stack_size` | stack of each spawned worker; the caller keeps its own |
| `caller_works` | `true` | `false`: the caller only waits and `threads` workers are spawned; if none spawns, it works anyway |

```zig
var cancel: std.atomic.Value(bool) = .init(false);
try coro.state_machine.runParallel(Countdown, tasks, .{ .threads = 4, .cancel = &cancel });
```

### `currentWorker() ?usize`

This thread's index in the innermost `runParallel` it is working in, in `0..opts.threads`,
or `null` outside one. A calling thread that works is index 0. Use it to reach per-worker
state from a `step`.

## `io`

Works with any `std.Io`: `std.Io.Threaded` (thread pool, every OS) or an evented `Io` where
available (`evented_available`).

### `spawnEach(io: std.Io, group: *std.Io.Group, n: usize, comptime function: anytype, ctx: anytype) void`

Spawns `function(ctx, i)` for each `i` in `0..n` into `group`. `function` has type
`fn (@TypeOf(ctx), usize) std.Io.Cancelable!void`. Does not wait; finish with
`group.await(io)` (wait for all) or `group.cancel(io)` (request cancellation, then wait).
Tasks may run inline, on other threads, or only at `await`, depending on the `Io`.

```zig
fn work(sum: *std.atomic.Value(u64), i: usize) std.Io.Cancelable!void {
    _ = sum.fetchAdd(i, .monotonic);
}

var threaded: std.Io.Threaded = .init(gpa, .{});
defer threaded.deinit();
const io = threaded.io();

var sum: std.atomic.Value(u64) = .init(0);
var group: std.Io.Group = .init;
coro.io.spawnEach(io, &group, 10_000, work, &sum);
try group.await(io);
```

### `Dispatcher(comptime Msg: type, comptime Ctx: type, comptime handler: fn (Ctx, Msg) void) type`

A pool of worker coroutines reading `Msg`s from a bounded `std.Io.Queue(Msg)` and calling
`handler(ctx, msg)`. Several workers call `handler` concurrently, so shared state behind
`ctx` must be thread-safe (unless you start one worker). Must not be moved after `start`.

| method | does | returns |
|---|---|---|
| `init(io, ctx, buffer: []Msg) Self` | creates a stopped dispatcher; `buffer` is the queue storage, its length the capacity | the dispatcher |
| `start(self: *Self, workers: usize)` | starts `workers` coroutines with `Group.concurrent` | `error.ConcurrencyUnavailable` if the `Io` can't run them concurrently |
| `submit(self: *Self, msg: Msg)` | enqueues; blocks while the queue is full | `error.Closed` after shutdown/cancel, `error.Canceled` |
| `shutdown(self: *Self)` | closes the queue, lets workers drain it, waits | `error.Canceled` if the caller was canceled |
| `cancel(self: *Self) void` | closes the queue and cancels workers; queued messages may be dropped | — |

```zig
fn handle(total: *u64, msg: u64) void {
    total.* += msg; // one worker below, so no race
}

var total: u64 = 0;
var buf: [64]u64 = undefined;
var d: coro.io.Dispatcher(u64, *u64, handle) = .init(io, &total, &buf);
try d.start(1);
for (0..100) |i| try d.submit(i);
try d.shutdown(); // total == 4950
```

## Processes

The "processes" variant in the benchmarks lives in `bench/main.zig` (the bench binary
re-executes itself in a `worker` mode). It is **not a library API**. A library version would
need the host program to cooperate (a hook at the start of `main` to detect worker mode,
plus a way to send inputs and results between processes). Proposal, if wanted: a small
`processes.run(io, gpa, n, ctx, task, .{ .processes = 0 })` + `processes.workerMain(...)`
pair limited to integer-range tasks with a `u64` reduction. Not implemented.

The examples on this page are compiled and run by the `README example` test in
`src/root.zig`.
