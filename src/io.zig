//! Coroutines on top of `std.Io` (Zig 0.17).
//!
//! The `Io` implementation decides how tasks run: `std.Io.Threaded` runs
//! them on a thread pool; an evented `Io` (`std.Io.Evented`, experimental
//! and not available on every OS) runs them as green threads. This module
//! only depends on the `Io` interface, so the same code works with both.
//!
//! * `spawnEach` + `Io.Group` — fire many small tasks, wait or cancel them as a group.
//! * `Dispatcher` — N long-lived worker coroutines pulling messages from an
//!   `Io.Queue` (a bounded channel) and dispatching them to a callback.
const std = @import("std");
const Io = std.Io;

/// True when the standard library provides an evented `Io` for this target.
pub const evented_available = @TypeOf(Io.Evented) == type and Io.Evented != void;

/// Spawns `function(ctx, i)` for i in `0..n` into `group` via `Group.async`.
pub fn spawnEach(io: Io, group: *Io.Group, n: usize, comptime function: anytype, ctx: anytype) void {
    for (0..n) |i| group.async(io, function, .{ ctx, i });
}

/// A pool of `workers` coroutines consuming `Msg`s from a bounded queue and
/// calling `handler(ctx, msg)` for each. Must not be moved after `start`.
pub fn Dispatcher(comptime Msg: type, comptime Ctx: type, comptime handler: fn (Ctx, Msg) void) type {
    return struct {
        const Self = @This();

        io: Io,
        ctx: Ctx,
        queue: Io.Queue(Msg),
        group: Io.Group = .init,

        /// `buffer` is the queue storage (caller-owned; its length is the capacity).
        pub fn init(io: Io, ctx: Ctx, buffer: []Msg) Self {
            return .{ .io = io, .ctx = ctx, .queue = .init(buffer) };
        }

        /// Starts the workers. They must run concurrently with the producer,
        /// so this uses `Group.concurrent` and fails with
        /// `error.ConcurrencyUnavailable` if the `Io` cannot provide that.
        pub fn start(self: *Self, workers: usize) Io.ConcurrentError!void {
            for (0..workers) |_| self.group.concurrent(self.io, worker, .{self}) catch |e| {
                self.cancel();
                return e;
            };
        }

        fn worker(self: *Self) Io.Cancelable!void {
            while (true) {
                const msg = self.queue.getOne(self.io) catch |e| switch (e) {
                    error.Closed => return,
                    error.Canceled => return error.Canceled,
                };
                handler(self.ctx, msg);
            }
        }

        /// Enqueues a message, blocking (cooperatively) while the queue is full.
        pub fn submit(self: *Self, msg: Msg) (Io.QueueClosedError || Io.Cancelable)!void {
            try self.queue.putOne(self.io, msg);
        }

        /// Graceful shutdown: closes the queue, lets workers drain it, waits.
        pub fn shutdown(self: *Self) Io.Cancelable!void {
            self.queue.close(self.io);
            try self.group.await(self.io);
        }

        /// Hard stop: cancels workers; queued messages may be dropped.
        pub fn cancel(self: *Self) void {
            self.queue.close(self.io);
            self.group.cancel(self.io);
        }
    };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn spin(seed: u64) u64 {
    var x = seed | 1;
    for (0..2000) |_| {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
    }
    return x;
}

const Record = struct {
    sum: std.atomic.Value(u64) = .init(0),
    count: std.atomic.Value(usize) = .init(0),
    threads: []std.Thread.Id,

    fn task(r: *Record, i: usize) Io.Cancelable!void {
        r.threads[i] = std.Thread.getCurrentId();
        _ = r.sum.fetchAdd(spin(i) & 0xff, .monotonic);
        _ = r.count.fetchAdd(1, .monotonic);
    }

    fn distinctThreads(r: *Record) !usize {
        const copy = try testing.allocator.dupe(std.Thread.Id, r.threads);
        defer testing.allocator.free(copy);
        std.mem.sortUnstable(std.Thread.Id, copy, {}, std.sort.asc(std.Thread.Id));
        var n: usize = 1;
        for (copy[1..], copy[0 .. copy.len - 1]) |a, b| n += @intFromBool(a != b);
        return n;
    }
};

fn expectedSum(n: usize) u64 {
    var s: u64 = 0;
    for (0..n) |i| s += spin(i) & 0xff;
    return s;
}

test "Group: 10k tasks on Io.Threaded complete, on several threads" {
    const n = 10_000;
    var threaded: Io.Threaded = .init(testing.allocator, .{ .async_limit = .limited(4) });
    defer threaded.deinit();
    const io = threaded.io();
    const ids = try testing.allocator.alloc(std.Thread.Id, n);
    defer testing.allocator.free(ids);
    var rec: Record = .{ .threads = ids };
    var group: Io.Group = .init;
    spawnEach(io, &group, n, Record.task, &rec);
    try group.await(io);
    try testing.expectEqual(@as(usize, n), rec.count.load(.monotonic));
    try testing.expectEqual(expectedSum(n), rec.sum.load(.monotonic));
    if ((std.Thread.getCpuCount() catch 1) > 1) try testing.expect(try rec.distinctThreads() >= 2);
}

const Sink = struct {
    sum: std.atomic.Value(u64) = .init(0),
    count: std.atomic.Value(usize) = .init(0),
    threads: [8]std.atomic.Value(u64) = @splat(.init(0)),
    fn handle(s: *Sink, msg: u64) void {
        _ = s.sum.fetchAdd(spin(msg) & 0xff, .monotonic);
        const idx = s.count.fetchAdd(1, .monotonic);
        _ = idx;
        const tid: u64 = @intCast(std.Thread.getCurrentId());
        for (&s.threads) |*slot| {
            const cur = slot.load(.monotonic);
            if (cur == tid) break;
            if (cur == 0) {
                if (slot.cmpxchgStrong(0, tid, .monotonic, .monotonic) == null) break;
            }
        }
    }
};

test "Dispatcher: queue + 4 workers process 10k messages, graceful shutdown" {
    const n = 10_000;
    var threaded: Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var sink: Sink = .{};
    var buf: [64]u64 = undefined;
    var d: Dispatcher(u64, *Sink, Sink.handle) = .init(io, &sink, &buf);
    try d.start(4);
    for (0..n) |i| try d.submit(i);
    try d.shutdown();
    try testing.expectEqual(@as(usize, n), sink.count.load(.monotonic));
    try testing.expectEqual(expectedSum(n), sink.sum.load(.monotonic));
    var distinct: usize = 0;
    for (&sink.threads) |*s| distinct += @intFromBool(s.load(.monotonic) != 0);
    if ((std.Thread.getCpuCount() catch 1) > 1) try testing.expect(distinct >= 2);
}

fn sleeperIo(io: Io, started: *std.atomic.Value(usize)) Io.Cancelable!void {
    _ = started.fetchAdd(1, .monotonic);
    while (true) try io.sleep(.fromMilliseconds(5), .awake);
}

test "Group.cancel stops never-ending tasks" {
    var threaded: Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var started: std.atomic.Value(usize) = .init(0);
    var group: Io.Group = .init;
    for (0..8) |_| try group.concurrent(io, sleeperIo, .{ io, &started });
    while (started.load(.monotonic) < 8) try io.sleep(.fromMilliseconds(1), .awake);
    group.cancel(io); // returns only after every task observed cancellation
    try testing.expectEqual(@as(usize, 8), started.load(.monotonic));
}

test "Dispatcher.cancel with blocked workers" {
    var threaded: Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var sink: Sink = .{};
    var buf: [4]u64 = undefined;
    var d: Dispatcher(u64, *Sink, Sink.handle) = .init(threaded.io(), &sink, &buf);
    try d.start(3);
    d.cancel();
    try testing.expectEqual(@as(usize, 0), sink.count.load(.monotonic));
}

test "evented availability flag is comptime-known" {
    comptime std.debug.assert(@TypeOf(evented_available) == bool);
}
