//! coroutines — two coroutine flavours for Zig 0.17, std only.
//!
//! Public API (see docs/API.md):
//!
//! * `state_machine` — stackless, allocation-free coroutines. A coroutine is
//!   any struct with `pub fn step(self: *T) Step`.
//!   `runAll` (one thread), `runParallel` (N threads), `ParallelOptions`,
//!   `Step`, `Error`, `Cursor` (the index queue behind `runParallel`), and
//!   `Pool` (long-lived workers for repeated runs).
//! * `io` — coroutines on `std.Io`: `spawnEach` (many tasks into an
//!   `Io.Group`), `Dispatcher` (worker pool over a bounded `Io.Queue`),
//!   `evented_available`.
//!
//! The "processes" variant in the benchmarks is benchmark code
//! (`bench/main.zig`), not part of the library API.

/// Stackless state-machine coroutines and their schedulers.
pub const state_machine = @import("state_machine.zig");
/// Coroutines on top of `std.Io`.
pub const io = @import("io.zig");

test {
    _ = state_machine;
    _ = io;
}

// Keeps the examples in README.md / docs/API.md compiling.
test "README example" {
    const std = @import("std");
    const Task = struct {
        left: u32,
        pub fn step(t: *@This()) state_machine.Step {
            t.left -= 1;
            return if (t.left == 0) .done else .yield;
        }
    };
    var tasks: [1000]Task = @splat(.{ .left = 10 });
    try std.testing.expectEqual(@as(u64, 10_000), try state_machine.runAll(Task, &tasks, null));
    tasks = @splat(.{ .left = 10 });
    try state_machine.runParallel(Task, &tasks, .{ .threads = 4 });

    const Work = struct {
        fn run(sum: *std.atomic.Value(u64), i: usize) std.Io.Cancelable!void {
            _ = sum.fetchAdd(i, .monotonic);
        }
        fn handle(total: *u64, msg: u64) void {
            total.* += msg;
        }
    };
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const tio = threaded.io();
    var sum: std.atomic.Value(u64) = .init(0);
    var group: std.Io.Group = .init;
    io.spawnEach(tio, &group, 100, Work.run, &sum);
    try group.await(tio);
    try std.testing.expectEqual(@as(u64, 4950), sum.load(.monotonic));

    var total: u64 = 0;
    var buf: [64]u64 = undefined;
    var d: io.Dispatcher(u64, *u64, Work.handle) = .init(tio, &total, &buf);
    try d.start(1);
    for (0..100) |i| try d.submit(i);
    try d.shutdown();
    try std.testing.expectEqual(@as(u64, 4950), total);
}
