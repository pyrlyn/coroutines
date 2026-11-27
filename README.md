<h1><picture><source media="(prefers-color-scheme: dark)" srcset="brand/logo-dark.svg"><img src="brand/logo.svg" width="32" height="32" alt="" align="absmiddle"></picture> coroutines</h1>

Two coroutine flavours for Zig 0.17.1, plus an evented runtime. Standard library only, no third-party dependencies; `src/vendor/` holds patched copies of two std files.

| module | what a coroutine is | switch | memory per task | parallelism |
|---|---|---|---|---|
| `coroutines.state_machine` | a struct with a state field and `pub fn step(*T) Step` (`.yield` / `.done`) | a function return + call | `@sizeOf(T)`, caller-provided storage, 0 allocations | `runParallel`: N OS threads, lock-free chunked work queue |
| `coroutines.io` | a function run through `std.Io` (`Io.Group`, `Io.Queue`) | whatever the `Io` does (thread handoff for `std.Io.Threaded`) | one allocation per task in `std.Io.Threaded` (64 B measured) | the `Io` thread pool |
| `coroutines.rt` | a struct with `Output` and `pub fn poll(*T, *rt.Context) rt.Poll(Output)`; waits (join, channel, semaphore) without a thread | a function return + call; wake-ups go to the worker's LIFO slot | one pooled 64 B+ frame, 0 allocations in steady state | own work-stealing pool (see [docs/rt.md](docs/rt.md)) |

## Using in your project

Requires Zig 0.17.1. No dependencies besides the standard library.

1. Add the package:

   ```sh
   zig fetch --save git+https://github.com/pyrlyn/coroutines
   ```

   Pin a commit with `git+https://github.com/pyrlyn/coroutines#<commit>` if you want a fixed revision.

2. Import the module in `build.zig`:

   ```zig
   const coroutines = b.dependency("coroutines", .{ .target = target, .optimize = optimize });
   exe.root_module.addImport("coroutines", coroutines.module("coroutines"));
   ```

3. Use it:

   ```zig
   const std = @import("std");
   const coro = @import("coroutines");

   const Countdown = struct {
       left: u32,
       pub fn step(c: *Countdown) coro.state_machine.Step {
           c.left -= 1;
           return if (c.left == 0) .done else .yield;
       }
   };

   fn work(sum: *std.atomic.Value(u64), i: usize) std.Io.Cancelable!void {
       _ = sum.fetchAdd(i, .monotonic);
   }

   pub fn main(init: std.process.Init) !void {
       // State machine: 1000 tasks on all cores, no allocation.
       var tasks: [1000]Countdown = @splat(.{ .left = 10 });
       try coro.state_machine.runParallel(Countdown, &tasks, .{});

       // std.Io: 10,000 tasks in a group.
       var sum: std.atomic.Value(u64) = .init(0);
       var group: std.Io.Group = .init;
       coro.io.spawnEach(init.io, &group, 10_000, work, &sum);
       try group.await(init.io);
   }
   ```

Full reference: [docs/API.md](docs/API.md).

## Tests

`zig build test` — 9 unit tests:

* state machine: 10k tasks round-robin with exact step count and results; 10k tasks on
  4 threads with ≥ 2 distinct threads observed; cancellation joins all workers.
* io: 10k tasks in an `Io.Group` with ≥ 2 distinct threads; a `Dispatcher` with 4 workers
  processing 10k messages and shutting down cleanly; `Group.cancel` stopping endless
  sleeping tasks; `Dispatcher.cancel` with blocked workers.

## Documentation

- [Design](docs/design.md): `state_machine`, `io` and `evented`, plus invariants.
- [`rt` runtime](docs/rt.md): the work-stealing scheduler.
- [API](docs/API.md): public surface.
- [Benchmarks](docs/benchmarks.md): results, process sweep, analysis and backends by task count.

## License

Licensed under GPL-3.0-or-later. See [LICENSE](LICENSE).
