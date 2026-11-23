# Design notes

See [README](../README.md) for a short overview and [API.md](API.md) for the public surface. Key invariants:

* `state_machine.runAll` permutes the task slice: finished tasks move to the end.
  The step count it returns equals the sum of `step` calls, which the tests check exactly.
* `state_machine.runParallel` never allocates. Workers share one `Cursor`; a chunk
  belongs to exactly one worker, so tasks need no synchronisation of their own.
  Shutdown order: every worker returns (queue empty or cancel observed) → caller joins
  all handles → result. Thread stacks default to `worker_stack_size` (1 MiB; 256 KiB fails
  to spawn with glibc on aarch64 Linux). `stack_size` raises that for deep recursion, and
  `caller_works = false` covers the one stack a run cannot choose, the caller's.
* `io.Dispatcher` must not move after `start` (workers hold a pointer to it).
  `shutdown` = `Queue.close` + `Group.await`; `cancel` = `Queue.close` + `Group.cancel`.

## Modules

### `state_machine`

* A coroutine is a plain struct; its progress lives in its own fields, so a "switch"
  is just returning from `step` and the scheduler calling the next task's `step`.
  No stacks, no allocation, no syscalls.
* `runAll(T, tasks, cancel)` — round-robin on the calling thread. Finished tasks are
  swapped to the end of the slice, so each round touches only live tasks.
* `runParallel(T, tasks, opts)` — up to `max_threads` (64) workers including the caller.
  Work distribution is one `Cursor` (`fetchAdd` of `chunk` tasks); a worker runs
  its chunk to completion and claims the next one. Thread handles live on the caller's
  stack. All threads are joined before returning, also on cancellation. Workers get
  `opts.stack_size` of stack; `opts.caller_works = false` leaves the caller waiting, so
  every step runs on such a stack. `currentWorker()` gives a step its worker's index.
* `Cursor` — that queue on its own: hands out `[0, total)` in chunks to any number of
  threads, for parallel loops over indices that are not coroutines.
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

### `evented`

A separate layer whose runtime owns an evented `std.Io` (fibers): io_uring on Linux, libdispatch on macOS.
A task blocked in `await`, a channel, the limiter or `sleep` suspends its fiber, not an OS thread.

```zig
const ev = coro.evented;
var rt: ev.Runtime = undefined;
try rt.init(gpa, .{}); // gpa must be thread-safe
defer rt.deinit();
const io = rt.io();

var f = try rt.spawn(work, .{ io, 1 }); // Io.Future
_ = f.await(io);

var scope: ev.Scope = .init(io); // structured: first error cancels the rest
try scope.spawn(fetch, .{ io, "a" });
try scope.spawn(fetch, .{ io, "b" });
try scope.join();

var buf: [64]u32 = undefined;
var ch: ev.Channel(u32) = .init(&buf); // bounded: send suspends while full
var permits: [8]u8 = undefined;
var limit: ev.Limiter = .init(io, &permits); // at most 8 holders, FIFO
```

`Scope`, `Channel` and `Limiter` only need an `Io`, so they also work on `std.Io.Threaded`.
Caveats with Zig 0.17.1 (details in `src/vendor/zig-0.17.1/README.md`):
* `std.Io.Evented` does not compile upstream. `evented` therefore uses patched copies of
  `Io/Uring.zig` and `Io/Dispatch.zig`; the patches only remove stale `net_accept` prongs.
* Upstream fiber switching misbehaves in optimized builds: a single spawn plus await aborts or returns
  garbage. `evented.available` is therefore false outside Debug, unless the root file sets
  `pub const coroutines_evented_allow_optimized = true`.
* On libdispatch, canceling a fiber that is in `sleep` or blocked on a contended queue is
  broken upstream. The tests that need it are skipped on macOS.
