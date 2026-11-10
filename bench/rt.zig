//! Benchmarks of `coroutines.rt` with the same workloads as the tokio and Go
//! programs in the comparison (see bench/results/rt-vs-tokio-go-*.md).
//! Output: "<name> <ns_per_op> <allocs_per_op> <bytes_per_op>" per line.
//! Usage: bench-rt [workers]   (workers for the multi-thread runs; 0 = CPUs)
const std = @import("std");
const coro = @import("coroutines");
const rt = coro.rt;
const Io = std.Io;
const Context = rt.Context;
const Poll = rt.Poll;

const Counting = struct {
    child: std.mem.Allocator,
    allocs: std.atomic.Value(u64) = .init(0),
    bytes: std.atomic.Value(u64) = .init(0),
    fn allocator(c: *Counting) std.mem.Allocator {
        return .{ .ptr = c, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(p: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const c: *Counting = @ptrCast(@alignCast(p));
        _ = c.allocs.fetchAdd(1, .monotonic);
        _ = c.bytes.fetchAdd(len, .monotonic);
        return c.child.rawAlloc(len, a, ra);
    }
    fn resize(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const c: *Counting = @ptrCast(@alignCast(p));
        return c.child.rawResize(m, a, n, ra);
    }
    fn remap(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const c: *Counting = @ptrCast(@alignCast(p));
        return c.child.rawRemap(m, a, n, ra);
    }
    fn free(p: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const c: *Counting = @ptrCast(@alignCast(p));
        c.child.rawFree(m, a, ra);
    }
    fn snap(c: *Counting) [2]u64 {
        return .{ c.allocs.load(.monotonic), c.bytes.load(.monotonic) };
    }
};

pub const SWITCHES = 20_000_000;
pub const SPAWN_N = 1_000_000;
pub const JOIN_ONE_N = 200_000;
pub const PINGPONG = 100_000;
pub const FANIN_N = 200_000;
pub const FANIN_CAP = 1024;
pub const SKEW_N = 10_000;
pub const SKEW_LIGHT = 1_000;
pub const SKEW_HEAVY = 100_000;

var g_io: Io = undefined;
var g_count: *Counting = undefined;
var g_phases = false;

fn now() i96 {
    return Io.Timestamp.now(g_io, .awake).toNanoseconds();
}

/// Measured interval, filled by the root task.
const Meter = struct {
    t0: i96 = 0,
    a0: [2]u64 = .{ 0, 0 },
    ns: i96 = 0,
    a: [2]u64 = .{ 0, 0 },
    fn start(m: *Meter) void {
        m.a0 = g_count.snap();
        m.t0 = now();
    }
    fn stop(m: *Meter) void {
        m.ns = now() - m.t0;
        const a1 = g_count.snap();
        m.a = .{ a1[0] - m.a0[0], a1[1] - m.a0[1] };
    }
    fn emit(m: *const Meter, name: []const u8, ops: u64) void {
        const o: f64 = @floatFromInt(ops);
        std.debug.print("{s} {d:.3} {d:.4} {d:.2}\n", .{
            name,
            @as(f64, @floatFromInt(m.ns)) / o,
            @as(f64, @floatFromInt(m.a[0])) / o,
            @as(f64, @floatFromInt(m.a[1])) / o,
        });
    }
};

const Tiny = struct {
    pub const Output = u64;
    i: u64,
    pub fn poll(t: *Tiny, cx: *Context) Poll(u64) {
        _ = cx;
        return .{ .ready = t.i *% 3 +% 1 };
    }
};

// ---- yield switch: two tasks yield to each other
const Yielder = struct {
    pub const Output = void;
    left: u64,
    pub fn poll(y: *Yielder, cx: *Context) Poll(void) {
        if (y.left == 0) return .{ .ready = {} };
        y.left -= 1;
        cx.yieldNow();
        return .pending;
    }
};
const SwitchRoot = struct {
    pub const Output = void;
    m: *Meter,
    h: [2]?rt.JoinHandle(Yielder) = .{ null, null },
    started: bool = false,
    pub fn poll(s: *SwitchRoot, cx: *Context) Poll(void) {
        if (!s.started) {
            s.started = true;
            s.m.start();
            for (&s.h) |*h| h.* = cx.runtime().spawn(Yielder, .{ .left = SWITCHES / 2 }) catch @panic("oom");
        }
        for (&s.h) |*slot| if (slot.*) |*h| switch (h.poll(cx)) {
            .pending => return .pending,
            .ready => slot.* = null,
        };
        s.m.stop();
        return .{ .ready = {} };
    }
};

// ---- spawn + join one task at a time
const JoinOne = struct {
    pub const Output = u64;
    m: *Meter,
    i: u64 = 0,
    sum: u64 = 0,
    h: ?rt.JoinHandle(Tiny) = null,
    pub fn poll(s: *JoinOne, cx: *Context) Poll(u64) {
        if (s.i == 0 and s.h == null) s.m.start();
        while (s.i < JOIN_ONE_N) {
            if (s.h == null) s.h = cx.runtime().spawn(Tiny, .{ .i = s.i }) catch @panic("oom");
            switch (s.h.?.poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    s.sum +%= r catch unreachable;
                    s.h = null;
                    s.i += 1;
                },
            }
        }
        s.m.stop();
        return .{ .ready = s.sum };
    }
};

// ---- spawn N, then join all (handles in a Vec, as in the tokio program)
const SpawnMany = struct {
    pub const Output = u64;
    m: *Meter,
    hs: std.ArrayList(rt.JoinHandle(Tiny)) = .empty,
    joined: usize = 0,
    sum: u64 = 0,
    started: bool = false,
    t_spawned: i96 = 0,
    pub fn poll(s: *SpawnMany, cx: *Context) Poll(u64) {
        if (!s.started) {
            s.started = true;
            s.m.start();
            s.hs.ensureTotalCapacity(g_count.allocator(), SPAWN_N) catch @panic("oom");
            for (0..SPAWN_N) |i| s.hs.appendAssumeCapacity(cx.runtime().spawn(Tiny, .{ .i = i }) catch @panic("oom"));
            s.t_spawned = now();
        }
        while (s.joined < s.hs.items.len) {
            switch (s.hs.items[s.joined].poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    s.sum +%= r catch unreachable;
                    s.joined += 1;
                },
            }
        }
        s.m.stop();
        if (g_phases) std.debug.print("  spawn phase {d} ns/op\n", .{@divTrunc(s.t_spawned - s.m.t0, SPAWN_N)});
        s.hs.deinit(g_count.allocator());
        return .{ .ready = s.sum };
    }
};

// ---- channel ping-pong, capacity 1 both ways
const Chan = rt.Channel(u32);
const Pong = struct {
    pub const Output = void;
    a: *Chan,
    b: *Chan,
    left: u32,
    v: ?u32 = null,
    rw: Chan.RecvWaiter = .{},
    sw: Chan.SendWaiter = .{},
    pub fn poll(p: *Pong, cx: *Context) Poll(void) {
        while (true) {
            if (p.v == null) {
                if (p.left == 0) return .{ .ready = {} };
                switch (p.a.recv(cx, &p.rw)) {
                    .pending => return .pending,
                    .ready => |v| p.v = v.?,
                }
            }
            switch (p.b.send(cx, &p.sw, p.v.? + 1)) {
                .pending => return .pending,
                .ready => |r| r catch unreachable,
            }
            p.v = null;
            p.left -= 1;
        }
    }
};
const PingRoot = struct {
    pub const Output = u32;
    m: *Meter,
    a: Chan,
    b: Chan,
    i: u32 = 0,
    v: u32 = 0,
    sent: bool = false,
    rw: Chan.RecvWaiter = .{},
    sw: Chan.SendWaiter = .{},
    h: ?rt.JoinHandle(Pong) = null,
    pub fn poll(p: *PingRoot, cx: *Context) Poll(u32) {
        if (p.h == null) {
            p.m.start();
            p.h = cx.runtime().spawn(Pong, .{ .a = &p.a, .b = &p.b, .left = PINGPONG }) catch @panic("oom");
        }
        while (p.i < PINGPONG) {
            if (!p.sent) {
                switch (p.a.send(cx, &p.sw, p.v)) {
                    .pending => return .pending,
                    .ready => |r| r catch unreachable,
                }
                p.sent = true;
            }
            switch (p.b.recv(cx, &p.rw)) {
                .pending => return .pending,
                .ready => |v| p.v = v.?,
            }
            p.sent = false;
            p.i += 1;
        }
        switch (p.h.?.poll(cx)) {
            .pending => return .pending,
            .ready => |r| r catch unreachable,
        }
        p.m.stop();
        return .{ .ready = p.v };
    }
};

// ---- fan-out N detached senders into one bounded channel, fan-in in the root
const Sender = struct {
    pub const Output = void;
    c: *rt.Channel(u64),
    v: u64,
    w: rt.Channel(u64).SendWaiter = .{},
    pub fn poll(s: *Sender, cx: *Context) Poll(void) {
        return switch (s.c.send(cx, &s.w, s.v)) {
            .pending => .pending,
            .ready => .{ .ready = {} },
        };
    }
};
const FanRoot = struct {
    pub const Output = u64;
    m: *Meter,
    c: *rt.Channel(u64),
    spawned: bool = false,
    got: usize = 0,
    sum: u64 = 0,
    w: rt.Channel(u64).RecvWaiter = .{},
    pub fn poll(f: *FanRoot, cx: *Context) Poll(u64) {
        if (!f.spawned) {
            f.spawned = true;
            f.m.start();
            for (0..FANIN_N) |i| cx.runtime().spawnDetached(Sender, .{ .c = f.c, .v = i }) catch @panic("oom");
        }
        while (f.got < FANIN_N) {
            switch (f.c.recv(cx, &f.w)) {
                .pending => return .pending,
                .ready => |v| {
                    f.sum +%= v.?;
                    f.got += 1;
                },
            }
        }
        f.m.stop();
        return .{ .ready = f.sum };
    }
};

// ---- skewed CPU work: 1% of tasks are 100x heavier
pub fn lcg(iters: u64, seed: u64) u64 {
    var x = seed;
    var i: u64 = 0;
    while (i < iters) : (i += 1) x = x *% 6364136223846793005 +% 1442695040888963407;
    return x;
}
const Work = struct {
    pub const Output = u64;
    i: u64,
    pub fn poll(w: *Work, cx: *Context) Poll(u64) {
        _ = cx;
        const iters: u64 = if (w.i % 100 == 0) SKEW_HEAVY else SKEW_LIGHT;
        return .{ .ready = lcg(iters, w.i) };
    }
};
const SkewRoot = struct {
    pub const Output = u64;
    m: *Meter,
    hs: []rt.JoinHandle(Work),
    started: bool = false,
    joined: usize = 0,
    sum: u64 = 0,
    pub fn poll(s: *SkewRoot, cx: *Context) Poll(u64) {
        if (!s.started) {
            s.started = true;
            s.m.start();
            for (s.hs, 0..) |*h, i| h.* = cx.runtime().spawn(Work, .{ .i = i }) catch @panic("oom");
        }
        while (s.joined < s.hs.len) {
            switch (s.hs[s.joined].poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    s.sum +%= r catch unreachable;
                    s.joined += 1;
                },
            }
        }
        s.m.stop();
        return .{ .ready = s.sum };
    }
};

fn runAll(gpa: std.mem.Allocator, opts: rt.Options, suffix: []const u8, which: []const u8) !void {
    var r: rt.Runtime = undefined;
    try r.init(gpa, g_io, opts);
    defer r.deinit();
    var name_buf: [64]u8 = undefined;
    const all = std.mem.eql(u8, which, "all");
    if (all or std.mem.indexOf(u8, which, "switch") != null) {
        var m: Meter = .{};
        try r.blockOn(SwitchRoot, .{ .m = &m });
        m.emit(try std.fmt.bufPrint(&name_buf, "switch_rt_{s}_yield", .{suffix}), SWITCHES);
    }
    if (all or std.mem.indexOf(u8, which, "joinone") != null) {
        var m: Meter = .{};
        std.mem.doNotOptimizeAway(try r.blockOn(JoinOne, .{ .m = &m }));
        m.emit(try std.fmt.bufPrint(&name_buf, "spawnjoin1_rt_{s}", .{suffix}), JOIN_ONE_N);
    }
    if (all or std.mem.indexOf(u8, which, "spawn") != null) {
        var m: Meter = .{};
        std.mem.doNotOptimizeAway(try r.blockOn(SpawnMany, .{ .m = &m }));
        m.emit(try std.fmt.bufPrint(&name_buf, "spawn_rt_{s}", .{suffix}), SPAWN_N);
    }
    if (all or std.mem.indexOf(u8, which, "pingpong") != null) {
        var m: Meter = .{};
        var ba: [1]u32 = undefined;
        var bb: [1]u32 = undefined;
        std.mem.doNotOptimizeAway(try r.blockOn(PingRoot, .{ .m = &m, .a = .init(&ba), .b = .init(&bb) }));
        m.emit(try std.fmt.bufPrint(&name_buf, "pingpong_rt_{s}", .{suffix}), PINGPONG);
    }
    if (all or std.mem.indexOf(u8, which, "fanin") != null) {
        var m: Meter = .{};
        const buf = try gpa.alloc(u64, FANIN_CAP);
        defer gpa.free(buf);
        var c: rt.Channel(u64) = .init(buf);
        std.mem.doNotOptimizeAway(try r.blockOn(FanRoot, .{ .m = &m, .c = &c }));
        m.emit(try std.fmt.bufPrint(&name_buf, "fanin_rt_{s}", .{suffix}), FANIN_N);
        // Let woken senders finish before `c` goes away.
        try r.blockOn(Drain, .{});
    }
    if (all or std.mem.indexOf(u8, which, "skew") != null) {
        var m: Meter = .{};
        const hs = try gpa.alloc(rt.JoinHandle(Work), SKEW_N);
        defer gpa.free(hs);
        std.mem.doNotOptimizeAway(try r.blockOn(SkewRoot, .{ .m = &m, .hs = hs }));
        m.emit(try std.fmt.bufPrint(&name_buf, "skew_rt_{s}", .{suffix}), SKEW_N);
    }
}

/// Yields a few thousand times so queued tasks run.
const Drain = struct {
    pub const Output = void;
    left: u32 = 100_000,
    pub fn poll(d: *Drain, cx: *Context) Poll(void) {
        if (d.left == 0) return .{ .ready = {} };
        d.left -= 1;
        cx.yieldNow();
        return .pending;
    }
};

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    var counting: Counting = .{ .child = std.heap.smp_allocator };
    g_count = &counting;
    const gpa = counting.allocator();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const which: []const u8 = if (args.len > 1) args[1] else "all";
    const workers: usize = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 0;
    g_phases = args.len > 3;
    try runAll(gpa, .{ .current_thread = true }, "ct", which);
    try runAll(gpa, .{ .workers = workers }, "mt", which);
}
