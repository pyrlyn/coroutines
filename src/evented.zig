//! Coroutines on an evented `std.Io`: green threads (fibers) where a blocked
//! task (`await`, a full or empty channel, a limiter, `sleep`) suspends only
//! its fiber. The OS thread stays free for other tasks.
//!
//! This layer is separate from `coroutines.io`, which stays on whatever `Io`
//! the caller passes (usually `std.Io.Threaded`). Here the runtime owns the
//! evented `Io` instance:
//!
//! * `Runtime` — init/deinit of the evented backend; `io()`, `spawn`.
//! * `Scope` — structured concurrency: tasks spawned into a scope are joined
//!   by `join`. The first error cancels the siblings and is returned.
//! * `Channel(T)` — bounded MPMC channel. `send` blocks (suspends) while full,
//!   which gives backpressure.
//! * `Limiter` — FIFO-fair concurrency limiter (at most N holders).
//!
//! `Scope`, `Channel` and `Limiter` only use the `Io` interface, so they also
//! work on `std.Io.Threaded`. There, a blocked task blocks its OS thread.
//!
//! Backends: io_uring on Linux and libdispatch on macOS (aarch64/x86_64),
//! through the patched copies in `vendor/zig-0.17.1` (see its README:
//! `std.Io.Evented` does not compile in Zig 0.17.x). `available` is false
//! elsewhere, and in optimized builds (see `allow_optimized`); `Runtime`
//! cannot be used then.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zig_0_17_1 = builtin.zig_version.major == 0 and builtin.zig_version.minor == 17 and builtin.zig_version.patch == 1;

/// The evented `Io` implementation used by `Runtime`, or `void`.
pub const Backend = if (!Io.fiber.supported or !zig_0_17_1) void else switch (builtin.os.tag) {
    .linux => @import("vendor/zig-0.17.1/Uring.zig"),
    .macos => @import("vendor/zig-0.17.1/Dispatch.zig"),
    else => void,
};

/// Which backend `Runtime` uses on this target.
pub const backend: enum { none, io_uring, dispatch } = if (Backend == void) .none else switch (builtin.os.tag) {
    .linux => .io_uring,
    .macos => .dispatch,
    else => unreachable,
};

/// Upstream fiber switching is broken in optimized builds of Zig 0.17.1:
/// a single `concurrent` + `await` aborts with an assertion in
/// `Future.await` (ReleaseSafe, io_uring), returns a garbage result
/// (ReleaseFast, libdispatch) or segfaults (ReleaseSmall, libdispatch).
/// The runtime is therefore only enabled in Debug builds, unless the root
/// file declares `pub const coroutines_evented_allow_optimized = true`
/// (the benchmarks do this, to measure despite the bug).
pub const allow_optimized = @hasDecl(root, "coroutines_evented_allow_optimized") and root.coroutines_evented_allow_optimized;
const root = @import("root");

/// True when `Runtime` works on this target and build mode.
pub const available = Backend != void and (builtin.mode == .debug or allow_optimized);

/// Owns one evented `Io` instance.
///
/// The value must not move after `init`, because the backend keeps pointers into it.
/// `init` and `deinit` must run on the same thread. That thread becomes the
/// runtime's main fiber: blocking calls made on it through `io()` suspend it,
/// while the backend keeps running other fibers.
pub const Runtime = struct {
    tracking: Tracking,
    backend: if (Backend != void) Backend else void,
    /// Live allocations right after `init`; `deinit` waits to get back here.
    baseline: usize,

    pub const Options = struct {
        /// Linux only: worker thread limit (null = CPU count - 1).
        thread_limit: ?usize = null,
    };

    /// `gpa` must be thread-safe: fibers are created and destroyed on the
    /// backend's threads.
    pub fn init(rt: *Runtime, gpa: Allocator, options: Options) !void {
        if (!available) @compileError("coroutines.evented: no evented backend for this target, Zig version or build mode (see `available`)");
        rt.tracking = .{ .child = gpa };
        rt.baseline = 0;
        const a = rt.tracking.allocator();
        switch (backend) {
            .io_uring => try rt.backend.init(a, .{ .thread_limit = options.thread_limit }),
            // Workaround for upstream bug 2 (vendor README): the backend's
            // own allocator mutex can yield outside a fiber.
            .dispatch => try rt.backend.init(a, .{ .backing_allocator_needs_mutex = false }),
            .none => unreachable,
        }
        rt.baseline = rt.tracking.live.load(.acquire);
    }

    /// Waits until fibers finished before `deinit` have been destroyed, then
    /// tears the backend down. All tasks must have been awaited or canceled.
    pub fn deinit(rt: *Runtime) void {
        if (Backend == void) unreachable;
        // Workaround for upstream bug 1 (vendor README): fibers are freed
        // asynchronously after they finish, possibly after the backend's
        // `deinit`. Yield on the main fiber until they are gone.
        const rio = rt.io();
        var tries: usize = 0;
        while (rt.tracking.live.load(.acquire) > rt.baseline and tries < 10_000) : (tries += 1) {
            rio.sleep(.fromMicroseconds(100), .awake) catch {};
        }
        rt.backend.deinit();
        rt.* = undefined;
    }

    pub fn io(rt: *Runtime) Io {
        if (Backend == void) unreachable;
        return rt.backend.io();
    }

    /// Starts `function(args...)` as a new fiber and returns its future.
    /// Await it with `future.await(io)` or cancel it with `future.cancel(io)`.
    /// The future must be awaited or canceled before `deinit`.
    pub fn spawn(
        rt: *Runtime,
        function: anytype,
        args: std.meta.ArgsTuple(@TypeOf(function)),
    ) Io.ConcurrentError!Io.Future(@typeInfo(@TypeOf(function)).@"fn".return_type.?) {
        return rt.io().concurrent(function, args);
    }
};

/// Counts live allocations so that `Runtime.deinit` can wait for the
/// backend's deferred frees. Thread-safe if `child` is.
const Tracking = struct {
    child: Allocator,
    live: std.atomic.Value(usize) = .init(0),

    fn allocator(t: *Tracking) Allocator {
        return .{ .ptr = t, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(p: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const t: *Tracking = @ptrCast(@alignCast(p));
        const ptr = t.child.rawAlloc(len, a, ra) orelse return null;
        _ = t.live.fetchAdd(1, .acq_rel);
        return ptr;
    }
    fn resize(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const t: *Tracking = @ptrCast(@alignCast(p));
        return t.child.rawResize(m, a, n, ra);
    }
    fn remap(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const t: *Tracking = @ptrCast(@alignCast(p));
        return t.child.rawRemap(m, a, n, ra);
    }
    fn free(p: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const t: *Tracking = @ptrCast(@alignCast(p));
        t.child.rawFree(m, a, ra);
        _ = t.live.fetchSub(1, .acq_rel);
    }
};

/// Structured concurrency over `Io.Group`. Every task spawned into a scope
/// is finished when `join` returns. The first task error (other than
/// `error.Canceled`) cancels the remaining tasks, and `join` returns it.
///
/// ```zig
/// var scope: Scope = .init(io);
/// try scope.spawn(fetch, .{ io, a });
/// try scope.spawn(fetch, .{ io, b });
/// try scope.join(); // first error of fetch(a) / fetch(b), siblings canceled
/// ```
///
/// Do not move it after the first `spawn`, and do not spawn after `join` has started.
pub const Scope = struct {
    io: Io,
    group: Io.Group = .init,
    /// Running tasks.
    pending: std.atomic.Value(usize) = .init(0),
    /// `@intFromError` of the first failure, 0 = none.
    first_error: std.atomic.Value(@Int(.unsigned, @bitSizeOf(anyerror))) = .init(0),
    /// Set when the first task fails or the last one finishes.
    wake: Io.Event = .unset,

    pub fn init(io: Io) Scope {
        return .{ .io = io };
    }

    /// Starts `function(args...)` in this scope. `function` returns `E!void`
    /// for any error set `E`. Fails only if the `Io` cannot run it concurrently.
    pub fn spawn(s: *Scope, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) Io.ConcurrentError!void {
        const Args = @TypeOf(args);
        const Wrapper = struct {
            fn run(scope: *Scope, a: Args) Io.Cancelable!void {
                defer scope.finishOne();
                @call(.auto, function, a) catch |err| {
                    if (@as(anyerror, err) == error.Canceled) return error.Canceled;
                    scope.fail(err);
                };
            }
        };
        _ = s.pending.fetchAdd(1, .acq_rel);
        s.group.concurrent(s.io, Wrapper.run, .{ s, args }) catch |e| {
            s.finishOne();
            return e;
        };
    }

    fn fail(s: *Scope, err: anyerror) void {
        if (s.first_error.cmpxchgStrong(0, @intFromError(err), .acq_rel, .acquire) == null) s.wake.set(s.io);
    }

    fn finishOne(s: *Scope) void {
        if (s.pending.fetchSub(1, .acq_rel) == 1) s.wake.set(s.io);
    }

    /// The first error so far, if any.
    pub fn firstError(s: *const Scope) ?anyerror {
        const e = s.first_error.load(.acquire);
        return if (e == 0) null else @errorFromInt(e);
    }

    /// Waits for every task. Returns the first task error, after canceling and
    /// joining the remaining tasks. If the caller is canceled while waiting,
    /// all tasks are canceled and `error.Canceled` is returned.
    pub fn join(s: *Scope) anyerror!void {
        if (s.pending.load(.acquire) != 0) {
            s.wake.wait(s.io) catch |e| {
                s.group.cancel(s.io);
                return e;
            };
        }
        if (s.firstError()) |e| {
            s.group.cancel(s.io);
            return e;
        }
        try s.group.await(s.io);
    }

    /// Cancels every task and waits for them.
    pub fn cancel(s: *Scope) void {
        s.group.cancel(s.io);
    }
};

/// Bounded multi-producer multi-consumer channel over `Io.Queue`.
/// `send` suspends while the buffer is full (backpressure) and `recv`
/// suspends while it is empty. Waiters are served first-in first-out, and a
/// send to a waiting receiver hands the value over directly.
/// `close` makes sends fail. Receivers still drain what is buffered, then
/// get `error.Closed`.
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Error = Io.QueueClosedError || Io.Cancelable;

        queue: Io.Queue(T),

        /// `buffer.len` is the capacity. Caller-owned; must outlive the channel.
        pub fn init(buffer: []T) Self {
            return .{ .queue = .init(buffer) };
        }

        pub fn capacity(c: *const Self) usize {
            return c.queue.capacity();
        }

        /// Suspends while the channel is full.
        pub fn send(c: *Self, io: Io, value: T) Error!void {
            return c.queue.putOne(io, value);
        }

        /// Suspends until all of `values` are in.
        pub fn sendAll(c: *Self, io: Io, values: []const T) Error!void {
            return c.queue.putAll(io, values);
        }

        /// Never suspends. Returns false if the channel is full.
        pub fn trySend(c: *Self, io: Io, value: T) Io.QueueClosedError!bool {
            return try c.queue.putUncancelable(io, &.{value}, 0) == 1;
        }

        /// Suspends while the channel is empty.
        pub fn recv(c: *Self, io: Io) Error!T {
            return c.queue.getOne(io);
        }

        /// Suspends until at least one value is available, then takes up to
        /// `buffer.len`. Returns how many were taken.
        pub fn recvMany(c: *Self, io: Io, buffer: []T) Error!usize {
            return c.queue.get(io, buffer, 1);
        }

        /// Never suspends. Returns null if the channel is empty but open.
        pub fn tryRecv(c: *Self, io: Io) Io.QueueClosedError!?T {
            var one: [1]T = undefined;
            return if (try c.queue.getUncancelable(io, &one, 0) == 1) one[0] else null;
        }

        /// Idempotent.
        pub fn close(c: *Self, io: Io) void {
            c.queue.close(io);
        }
    };
}

/// Concurrency limiter: at most `permits` holders at a time. Waiters get
/// permits first-in first-out, and a release hands the permit straight to the
/// oldest waiter. `acquire` is a cancelation point. It is built on an
/// `Io.Queue` of tokens, so a blocked `acquire` suspends only its fiber
/// on an evented `Io`.
pub const Limiter = struct {
    tokens: Io.Queue(u8),

    /// `buffer.len` is the number of permits. Caller-owned; must outlive the limiter.
    pub fn init(io: Io, buffer: []u8) Limiter {
        var l: Limiter = .{ .tokens = .init(buffer) };
        @memset(buffer, 0);
        const scratch: [64]u8 = @splat(0);
        var left = buffer.len;
        while (left > 0) {
            const k = @min(left, scratch.len);
            left -= l.tokens.putUncancelable(io, scratch[0..k], k) catch unreachable;
        }
        return l;
    }

    pub fn permits(l: *const Limiter) usize {
        return l.tokens.capacity();
    }

    /// Suspends until a permit is free.
    pub fn acquire(l: *Limiter, io: Io) Io.Cancelable!void {
        _ = l.tokens.getOne(io) catch |e| switch (e) {
            error.Closed => unreachable, // never closed
            error.Canceled => return error.Canceled,
        };
    }

    /// Never suspends.
    pub fn tryAcquire(l: *Limiter, io: Io) bool {
        var one: [1]u8 = undefined;
        return (l.tokens.getUncancelable(io, &one, 0) catch unreachable) == 1;
    }

    /// Returns a permit. Must pair with a successful `acquire`/`tryAcquire`.
    pub fn release(l: *Limiter, io: Io) void {
        l.tokens.putOneUncancelable(io, 0) catch unreachable;
    }

    /// `acquire`, call `function(args...)`, `release`.
    pub fn run(
        l: *Limiter,
        io: Io,
        function: anytype,
        args: std.meta.ArgsTuple(@TypeOf(function)),
    ) (Io.Cancelable || ErrorOf(@TypeOf(function)))!PayloadOf(@TypeOf(function)) {
        try l.acquire(io);
        defer l.release(io);
        return @call(.auto, function, args);
    }
};

fn ReturnOf(comptime F: type) type {
    return @typeInfo(F).@"fn".return_type.?;
}
fn ErrorOf(comptime F: type) type {
    const R = ReturnOf(F);
    return switch (@typeInfo(R)) {
        .error_union => |eu| eu.error_set,
        else => error{},
    };
}
fn PayloadOf(comptime F: type) type {
    const R = ReturnOf(F);
    return switch (@typeInfo(R)) {
        .error_union => |eu| eu.payload,
        else => R,
    };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const cio = @import("io.zig");

/// The tests below run on a fresh `Runtime` each, or skip without a backend.
fn testRuntime(rt: *Runtime) !Io {
    if (!available) return error.SkipZigTest;
    try rt.init(testing.allocator, .{});
    return rt.io();
}

/// Skip tests that need cancellation of suspended fibers on libdispatch
/// (upstream bugs 3 and 4 in vendor/zig-0.17.1/README.md).
fn skipOnDispatchCancel() !void {
    if (backend == .dispatch) return error.SkipZigTest;
}

fn double(x: u64) u64 {
    return 2 * x;
}

test "Runtime: spawn and await" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var futures: [16]Io.Future(u64) = undefined;
    for (&futures, 0..) |*f, i| f.* = try rt.spawn(double, .{i});
    var sum: u64 = 0;
    for (&futures) |*f| sum += f.await(io);
    try testing.expectEqual(@as(u64, 2 * 120), sum);
}

fn add(sum: *std.atomic.Value(u64), i: usize) Io.Cancelable!void {
    _ = sum.fetchAdd(i, .monotonic);
}

test "Runtime: io.spawnEach runs 10k tasks" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var sum: std.atomic.Value(u64) = .init(0);
    var group: Io.Group = .init;
    cio.spawnEach(io, &group, 10_000, add, &sum);
    try group.await(io);
    try testing.expectEqual(@as(u64, 49_995_000), sum.load(.monotonic));
}

fn addMsg(sum: *std.atomic.Value(u64), msg: u64) void {
    _ = sum.fetchAdd(msg, .monotonic);
}

test "Runtime: io.Dispatcher with 4 workers, 10k messages" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var sum: std.atomic.Value(u64) = .init(0);
    var buf: [64]u64 = undefined;
    var d: cio.Dispatcher(u64, *std.atomic.Value(u64), addMsg) = .init(io, &sum, &buf);
    try d.start(4);
    for (0..10_000) |i| try d.submit(i);
    try d.shutdown();
    try testing.expectEqual(@as(u64, 49_995_000), sum.load(.monotonic));
}

fn pong(io: Io, a: *Channel(u32), b: *Channel(u32), n: usize) Channel(u32).Error!void {
    for (0..n) |_| try b.send(io, (try a.recv(io)) + 1);
}

test "Channel: ping-pong over 1-slot channels" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var ba: [1]u32 = undefined;
    var bb: [1]u32 = undefined;
    var a: Channel(u32) = .init(&ba);
    var b: Channel(u32) = .init(&bb);
    const n = 10_000;
    var f = try rt.spawn(pong, .{ io, &a, &b, n });
    var v: u32 = 0;
    for (0..n) |_| {
        try a.send(io, v);
        v = try b.recv(io);
    }
    try f.await(io);
    try testing.expectEqual(@as(u32, n), v);
}

fn produce(io: Io, c: *Channel(u32), n: u32, sent: *std.atomic.Value(u32)) Channel(u32).Error!void {
    for (0..n) |i| {
        try c.send(io, @intCast(i));
        _ = sent.fetchAdd(1, .release);
    }
    c.close(io);
}

test "Channel: backpressure blocks the producer at capacity, close drains" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var buf: [4]u32 = undefined;
    var c: Channel(u32) = .init(&buf);
    var sent: std.atomic.Value(u32) = .init(0);
    var f = try rt.spawn(produce, .{ io, &c, 100, &sent });
    // Nobody receives yet: the producer must stop at the capacity.
    var waited: usize = 0;
    while (sent.load(.acquire) < 4 and waited < 2000) : (waited += 1) try io.sleep(.fromMilliseconds(1), .awake);
    try io.sleep(.fromMilliseconds(20), .awake);
    try testing.expectEqual(@as(u32, 4), sent.load(.acquire));
    try testing.expect(!try c.trySend(io, 999));
    var got: u32 = 0;
    var expect: u32 = 0;
    while (c.recv(io)) |v| : (got += 1) {
        try testing.expectEqual(expect, v);
        expect += 1;
    } else |e| try testing.expectEqual(error.Closed, e);
    try f.await(io);
    try testing.expectEqual(@as(u32, 100), got);
    try testing.expectError(error.Closed, c.tryRecv(io));
}

test "Channel: tryRecv on an empty open channel" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var buf: [2]u8 = undefined;
    var c: Channel(u8) = .init(&buf);
    try testing.expectEqual(@as(?u8, null), try c.tryRecv(io));
    try testing.expect(try c.trySend(io, 7));
    try testing.expectEqual(@as(?u8, 7), try c.tryRecv(io));
}

const Gauge = struct {
    now: std.atomic.Value(usize) = .init(0),
    max: std.atomic.Value(usize) = .init(0),
    done: std.atomic.Value(usize) = .init(0),

    fn hold(g: *Gauge, io: Io) Io.Cancelable!void {
        const cur = g.now.fetchAdd(1, .acq_rel) + 1;
        _ = g.max.fetchMax(cur, .acq_rel);
        try io.sleep(.fromMilliseconds(2), .awake);
        _ = g.now.fetchSub(1, .acq_rel);
        _ = g.done.fetchAdd(1, .acq_rel);
    }
};

fn limited(l: *Limiter, io: Io, g: *Gauge) Io.Cancelable!void {
    try l.run(io, Gauge.hold, .{ g, io });
}

test "Limiter: never more than N holders, all tasks finish" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var permits: [3]u8 = undefined;
    var l: Limiter = .init(io, &permits);
    try testing.expectEqual(@as(usize, 3), l.permits());
    var g: Gauge = .{};
    var scope: Scope = .init(io);
    for (0..24) |_| try scope.spawn(limited, .{ &l, io, &g });
    try scope.join();
    try testing.expectEqual(@as(usize, 24), g.done.load(.acquire));
    try testing.expect(g.max.load(.acquire) <= 3);
    try testing.expect(g.max.load(.acquire) >= 1);
    try testing.expect(l.tryAcquire(io));
    l.release(io);
}

fn ok(n: *std.atomic.Value(usize)) error{Boom}!void {
    _ = n.fetchAdd(1, .acq_rel);
}

test "Scope: join waits for every task" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var n: std.atomic.Value(usize) = .init(0);
    var scope: Scope = .init(io);
    for (0..100) |_| try scope.spawn(ok, .{&n});
    try scope.join();
    try testing.expectEqual(@as(usize, 100), n.load(.acquire));
    try testing.expectEqual(@as(?anyerror, null), scope.firstError());
}

test "Scope: empty join returns at once" {
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var scope: Scope = .init(io);
    try scope.join();
}

fn boom() error{Boom}!void {
    return error.Boom;
}

fn waitForever(c: *Channel(u8), io: Io, canceled: *std.atomic.Value(usize)) Channel(u8).Error!void {
    _ = c.recv(io) catch |e| {
        if (e == error.Canceled) _ = canceled.fetchAdd(1, .acq_rel);
        return e;
    };
}

test "Scope: first error cancels blocked siblings and is returned" {
    try skipOnDispatchCancel();
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var buf: [1]u8 = undefined;
    var c: Channel(u8) = .init(&buf);
    var canceled: std.atomic.Value(usize) = .init(0);
    var scope: Scope = .init(io);
    for (0..4) |_| try scope.spawn(waitForever, .{ &c, io, &canceled });
    try scope.spawn(boom, .{});
    try testing.expectError(error.Boom, scope.join());
    try testing.expectEqual(@as(usize, 4), canceled.load(.acquire));
}

test "Scope on Io.Threaded: first error cancels siblings" {
    var threaded: Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var buf: [1]u8 = undefined;
    var c: Channel(u8) = .init(&buf);
    var canceled: std.atomic.Value(usize) = .init(0);
    var scope: Scope = .init(io);
    for (0..4) |_| try scope.spawn(waitForever, .{ &c, io, &canceled });
    try scope.spawn(boom, .{});
    try testing.expectError(error.Boom, scope.join());
    try testing.expectEqual(@as(usize, 4), canceled.load(.acquire));
}

test "Limiter and Channel on Io.Threaded" {
    var threaded: Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var permits: [2]u8 = undefined;
    var l: Limiter = .init(io, &permits);
    var g: Gauge = .{};
    var scope: Scope = .init(io);
    for (0..8) |_| try scope.spawn(limited, .{ &l, io, &g });
    try scope.join();
    try testing.expectEqual(@as(usize, 8), g.done.load(.acquire));
    try testing.expect(g.max.load(.acquire) <= 2);
}

test "Runtime: Future.cancel interrupts a blocked receive" {
    try skipOnDispatchCancel();
    var rt: Runtime = undefined;
    const io = try testRuntime(&rt);
    defer rt.deinit();
    var buf: [1]u8 = undefined;
    var c: Channel(u8) = .init(&buf);
    var canceled: std.atomic.Value(usize) = .init(0);
    var f = try rt.spawn(waitForever, .{ &c, io, &canceled });
    try io.sleep(.fromMilliseconds(5), .awake);
    try testing.expectError(error.Canceled, f.cancel(io));
}

test "backend is known at comptime" {
    comptime std.debug.assert(!available or backend != .none);
}
