//! Tests for `rt`: both scheduler modes, joins, channels, semaphores,
//! cancellation, outside spawners, stress and leak checks.
const std = @import("std");
const rt = @import("../rt.zig");
const testing = std.testing;
const Context = rt.Context;
const Poll = rt.Poll;

const Leaf = struct {
    pub const Output = u64;
    v: u64,
    pub fn poll(self: *Leaf, cx: *Context) Poll(u64) {
        _ = cx;
        return .{ .ready = self.v * 2 };
    }
};

/// Spawns and joins one child at a time.
const Serial = struct {
    pub const Output = u64;
    n: u64,
    i: u64 = 0,
    sum: u64 = 0,
    h: ?rt.JoinHandle(Leaf) = null,
    pub fn poll(self: *Serial, cx: *Context) Poll(u64) {
        while (self.i < self.n) {
            if (self.h == null) self.h = cx.runtime().spawn(Leaf, .{ .v = self.i }) catch @panic("oom");
            switch (self.h.?.poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    self.sum += r catch unreachable;
                    self.h = null;
                    self.i += 1;
                },
            }
        }
        return .{ .ready = self.sum };
    }
};

/// Spawns n children first, then joins them all.
const Many = struct {
    pub const Output = u64;
    hs: []rt.JoinHandle(Leaf),
    spawned: usize = 0,
    joined: usize = 0,
    sum: u64 = 0,
    pub fn poll(self: *Many, cx: *Context) Poll(u64) {
        while (self.spawned < self.hs.len) : (self.spawned += 1)
            self.hs[self.spawned] = cx.runtime().spawn(Leaf, .{ .v = self.spawned }) catch @panic("oom");
        while (self.joined < self.hs.len) {
            switch (self.hs[self.joined].poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    self.sum += r catch unreachable;
                    self.joined += 1;
                },
            }
        }
        return .{ .ready = self.sum };
    }
};

fn expectSum(n: u64, got: u64) !void {
    try testing.expectEqual(n * (n - 1), got);
}

/// Yields until it is the only live task: detached tasks that were woken
/// but not yet run get to finish.
const Settle = struct {
    pub const Output = void;
    left: u32 = 10_000_000,
    pub fn poll(self: *Settle, cx: *Context) Poll(void) {
        if (cx.runtime().liveTasks() <= 1 or self.left == 0) return .{ .ready = {} };
        self.left -= 1;
        cx.yieldNow();
        return .pending;
    }
};

fn withRuntime(opts: rt.Options, comptime f: fn (*rt.Runtime) anyerror!void) !void {
    var r: rt.Runtime = undefined;
    try r.init(testing.allocator, testing.io, opts);
    defer r.deinit();
    try f(&r);
    if (std.debug.runtime_safety) {
        try r.blockOn(Settle, .{});
        if (r.liveTasks() != 0) std.debug.print("mode {any}: live {d}\n", .{ opts, r.liveTasks() });
        try testing.expectEqual(@as(usize, 0), r.liveTasks());
    }
}

const modes = [_]rt.Options{ .{ .current_thread = true }, .{ .workers = 1 }, .{ .workers = 4 } };

test "spawn + join one at a time" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            try expectSum(5000, try r.blockOn(Serial, .{ .n = 5000 }));
        }
    }.f);
}

test "spawn many then join all" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const n = 50_000;
            const hs = try testing.allocator.alloc(rt.JoinHandle(Leaf), n);
            defer testing.allocator.free(hs);
            try expectSum(n, try r.blockOn(Many, .{ .hs = hs }));
            // A second blockOn on the same runtime reuses frames.
            try expectSum(n, try r.blockOn(Many, .{ .hs = hs }));
        }
    }.f);
}

const Chan = rt.Channel(u32);

const Pong = struct {
    pub const Output = void;
    a: *Chan,
    b: *Chan,
    left: u32,
    rw: Chan.RecvWaiter = .{},
    sw: Chan.SendWaiter = .{},
    v: ?u32 = null,
    pub fn poll(self: *Pong, cx: *Context) Poll(void) {
        while (true) {
            if (self.v == null) {
                if (self.left == 0) return .{ .ready = {} };
                switch (self.a.recv(cx, &self.rw)) {
                    .pending => return .pending,
                    .ready => |v| self.v = v.?,
                }
            }
            switch (self.b.send(cx, &self.sw, self.v.? + 1)) {
                .pending => return .pending,
                .ready => |r| r catch unreachable,
            }
            self.v = null;
            self.left -= 1;
        }
    }
};

const Ping = struct {
    pub const Output = u32;
    a: *Chan,
    b: *Chan,
    n: u32,
    i: u32 = 0,
    v: u32 = 0,
    sent: bool = false,
    rw: Chan.RecvWaiter = .{},
    sw: Chan.SendWaiter = .{},
    h: ?rt.JoinHandle(Pong) = null,
    pub fn poll(self: *Ping, cx: *Context) Poll(u32) {
        if (self.h == null) self.h = cx.runtime().spawn(Pong, .{ .a = self.a, .b = self.b, .left = self.n }) catch @panic("oom");
        while (self.i < self.n) {
            if (!self.sent) {
                switch (self.a.send(cx, &self.sw, self.v)) {
                    .pending => return .pending,
                    .ready => |r| r catch unreachable,
                }
                self.sent = true;
            }
            switch (self.b.recv(cx, &self.rw)) {
                .pending => return .pending,
                .ready => |v| self.v = v.?,
            }
            self.sent = false;
            self.i += 1;
        }
        switch (self.h.?.poll(cx)) {
            .pending => return .pending,
            .ready => |r| r catch unreachable,
        }
        return .{ .ready = self.v };
    }
};

test "channel ping-pong" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            inline for (.{ 0, 1, 4 }) |cap| {
                var ba: [cap]u32 = undefined;
                var bb: [cap]u32 = undefined;
                var a: Chan = .init(&ba);
                var b: Chan = .init(&bb);
                try testing.expectEqual(@as(u32, 10_000), try r.blockOn(Ping, .{ .a = &a, .b = &b, .n = 10_000 }));
            }
        }
    }.f);
}

const Sender = struct {
    pub const Output = void;
    c: *Chan,
    v: u32,
    w: Chan.SendWaiter = .{},
    pub fn poll(self: *Sender, cx: *Context) Poll(void) {
        return switch (self.c.send(cx, &self.w, self.v)) {
            .pending => .pending,
            .ready => |r| blk: {
                r catch unreachable;
                break :blk .{ .ready = {} };
            },
        };
    }
};

/// Fan-out n detached senders into a small channel, fan-in in the root.
const FanIn = struct {
    pub const Output = u64;
    c: *Chan,
    n: u32,
    spawned: u32 = 0,
    got: u32 = 0,
    sum: u64 = 0,
    w: Chan.RecvWaiter = .{},
    pub fn poll(self: *FanIn, cx: *Context) Poll(u64) {
        while (self.spawned < self.n) : (self.spawned += 1)
            cx.runtime().spawnDetached(Sender, .{ .c = self.c, .v = self.spawned }) catch @panic("oom");
        while (self.got < self.n) {
            switch (self.c.recv(cx, &self.w)) {
                .pending => return .pending,
                .ready => |v| {
                    self.sum += v.?;
                    self.got += 1;
                },
            }
        }
        return .{ .ready = self.sum };
    }
};

test "fan-out / fan-in through a bounded channel parks senders" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            var buf: [16]u32 = undefined;
            var c: Chan = .init(&buf);
            const n = 20_000;
            try testing.expectEqual(@as(u64, n * (n - 1) / 2), try r.blockOn(FanIn, .{ .c = &c, .n = n }));
            try testing.expectError(error.Empty, c.tryRecv());
            // Woken senders still have to run once; keep `c` alive until then.
            try r.blockOn(Settle, .{});
        }
    }.f);
}

const Limited = struct {
    pub const Output = void;
    sem: *rt.Semaphore,
    cur: *std.atomic.Value(u32),
    max: *std.atomic.Value(u32),
    w: rt.Semaphore.Waiter = .{},
    holding: bool = false,
    yields: u8 = 0,
    pub fn poll(self: *Limited, cx: *Context) Poll(void) {
        if (!self.holding) {
            switch (self.sem.acquire(cx, &self.w)) {
                .pending => return .pending,
                .ready => {},
            }
            self.holding = true;
            const c = self.cur.fetchAdd(1, .acq_rel) + 1;
            _ = self.max.fetchMax(c, .acq_rel);
        }
        if (self.yields < 3) {
            self.yields += 1;
            cx.yieldNow();
            return .pending;
        }
        _ = self.cur.fetchSub(1, .acq_rel);
        self.sem.release();
        return .{ .ready = {} };
    }
};

const SemRoot = struct {
    pub const Output = void;
    hs: []rt.JoinHandle(Limited),
    sem: *rt.Semaphore,
    cur: *std.atomic.Value(u32),
    max: *std.atomic.Value(u32),
    started: bool = false,
    joined: usize = 0,
    pub fn poll(self: *SemRoot, cx: *Context) Poll(void) {
        if (!self.started) {
            for (self.hs) |*h| h.* = cx.runtime().spawn(Limited, .{ .sem = self.sem, .cur = self.cur, .max = self.max }) catch @panic("oom");
            self.started = true;
        }
        while (self.joined < self.hs.len) {
            switch (self.hs[self.joined].poll(cx)) {
                .pending => return .pending,
                .ready => self.joined += 1,
            }
        }
        return .{ .ready = {} };
    }
};

test "semaphore caps concurrency" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            var sem: rt.Semaphore = .init(3);
            var cur: std.atomic.Value(u32) = .init(0);
            var max: std.atomic.Value(u32) = .init(0);
            const hs = try testing.allocator.alloc(rt.JoinHandle(Limited), 2000);
            defer testing.allocator.free(hs);
            try r.blockOn(SemRoot, .{ .hs = hs, .sem = &sem, .cur = &cur, .max = &max });
            try testing.expect(max.load(.acquire) <= 3);
            try testing.expect(max.load(.acquire) >= 1);
            try testing.expectEqual(@as(usize, 3), sem.available());
        }
    }.f);
}

/// Waits on a channel nobody writes to; must be aborted.
const Stuck = struct {
    pub const Output = u32;
    c: *Chan,
    deinits: *u32,
    w: Chan.RecvWaiter = .{},
    pub fn poll(self: *Stuck, cx: *Context) Poll(u32) {
        return switch (self.c.recv(cx, &self.w)) {
            .pending => .pending,
            .ready => |v| .{ .ready = v orelse 0 },
        };
    }
    pub fn deinit(self: *Stuck) void {
        self.c.cancelRecv(&self.w);
        self.deinits.* += 1;
    }
};

const AbortRoot = struct {
    pub const Output = bool;
    c: *Chan,
    deinits: *u32,
    h: ?rt.JoinHandle(Stuck) = null,
    polls: u32 = 0,
    pub fn poll(self: *AbortRoot, cx: *Context) Poll(bool) {
        self.polls += 1;
        if (self.h == null) {
            self.h = cx.runtime().spawn(Stuck, .{ .c = self.c, .deinits = self.deinits }) catch @panic("oom");
            cx.yieldNow(); // let it register as a waiter
            return .pending;
        }
        if (self.polls == 2) self.h.?.abort();
        return switch (self.h.?.poll(cx)) {
            .pending => .pending,
            .ready => |r| .{ .ready = if (r) |_| false else |e| e == error.Canceled },
        };
    }
};

test "abort cancels a waiting task and runs deinit" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            var buf: [1]u32 = undefined;
            var c: Chan = .init(&buf);
            var deinits: u32 = 0;
            try testing.expect(try r.blockOn(AbortRoot, .{ .c = &c, .deinits = &deinits }));
            try testing.expectEqual(@as(u32, 1), deinits);
            // The aborted receiver left the channel: a send must buffer.
            try c.trySend(7);
            try testing.expectEqual(@as(u32, 7), try c.tryRecv());
        }
    }.f);
}

test "close wakes receivers with null and senders with Closed" {
    try withRuntime(.{ .workers = 2 }, struct {
        const Recv = struct {
            pub const Output = ?u32;
            c: *Chan,
            w: Chan.RecvWaiter = .{},
            pub fn poll(self: *@This(), cx: *Context) Poll(?u32) {
                return switch (self.c.recv(cx, &self.w)) {
                    .pending => .pending,
                    .ready => |v| .{ .ready = v },
                };
            }
        };
        const Root = struct {
            pub const Output = bool;
            c: *Chan,
            h: ?rt.JoinHandle(Recv) = null,
            closed: bool = false,
            pub fn poll(self: *@This(), cx: *Context) Poll(bool) {
                if (self.h == null) {
                    self.h = cx.runtime().spawn(Recv, .{ .c = self.c }) catch @panic("oom");
                    cx.yieldNow();
                    return .pending;
                }
                if (!self.closed) {
                    self.closed = true;
                    self.c.close();
                }
                return switch (self.h.?.poll(cx)) {
                    .pending => .pending,
                    .ready => |r| .{ .ready = (r catch unreachable) == null },
                };
            }
        };
        fn f(r: *rt.Runtime) !void {
            var c: Chan = .init(&.{});
            try testing.expect(try r.blockOn(Root, .{ .c = &c }));
            try testing.expectError(error.Closed, c.trySend(1));
        }
    }.f);
}

// Tasks spawned by plain OS threads (outside the runtime).
test "wakers and spawns from outside threads" {
    try withRuntime(.{ .workers = 3 }, struct {
        const Root = struct {
            pub const Output = u64;
            c: *Chan,
            n: u32,
            got: u32 = 0,
            sum: u64 = 0,
            w: Chan.RecvWaiter = .{},
            pub fn poll(self: *@This(), cx: *Context) Poll(u64) {
                while (self.got < self.n) {
                    switch (self.c.recv(cx, &self.w)) {
                        .pending => return .pending,
                        .ready => |v| {
                            self.sum += v.?;
                            self.got += 1;
                        },
                    }
                }
                return .{ .ready = self.sum };
            }
        };
        fn producer(r: *rt.Runtime, c: *Chan, base: u32) void {
            for (0..1000) |i| r.spawnDetached(Sender, .{ .c = c, .v = base + @as(u32, @intCast(i)) }) catch @panic("oom");
        }
        fn f(r: *rt.Runtime) !void {
            var buf: [8]u32 = undefined;
            var c: Chan = .init(&buf);
            var th: [4]std.Thread = undefined;
            for (&th, 0..) |*t, k| t.* = try std.Thread.spawn(.{}, producer, .{ r, &c, @as(u32, @intCast(k * 1000)) });
            const sum = try r.blockOn(Root, .{ .c = &c, .n = 4000 });
            for (th) |t| t.join();
            try testing.expectEqual(@as(u64, 4000 * 3999 / 2), sum);
        }
    }.f);
}

test "stress: many runtimes, nested spawns, random joins" {
    const Tree = struct {
        pub const Output = u64;
        depth: u8,
        hs: [3]?rt.JoinHandle(@This()) = @splat(null),
        started: bool = false,
        acc: u64 = 1,
        pub fn poll(self: *@This(), cx: *Context) Poll(u64) {
            if (self.depth == 0) return .{ .ready = 1 };
            if (!self.started) {
                self.started = true;
                for (&self.hs) |*h| h.* = cx.runtime().spawn(@This(), .{ .depth = self.depth - 1 }) catch @panic("oom");
            }
            for (&self.hs) |*slot| if (slot.*) |*h| switch (h.poll(cx)) {
                .pending => return .pending,
                .ready => |r| {
                    self.acc += r catch unreachable;
                    slot.* = null;
                },
            };
            return .{ .ready = self.acc };
        }
    };
    for (0..20) |round| {
        var r: rt.Runtime = undefined;
        try r.init(testing.allocator, testing.io, .{ .workers = 1 + round % 6, .current_thread = round % 7 == 0 });
        defer r.deinit();
        // 3-ary tree of depth 7: (3^8 - 1) / 2 nodes.
        try testing.expectEqual(@as(u64, 3280), try r.blockOn(Tree, .{ .depth = 7 }));
        try testing.expectEqual(@as(usize, 0), r.liveTasks());
    }
}

test "big task frames use the allocator directly" {
    try withRuntime(.{ .workers = 2 }, struct {
        const Big = struct {
            pub const Output = u8;
            pad: [10000]u8 = @splat(1),
            pub fn poll(self: *@This(), cx: *Context) Poll(u8) {
                _ = cx;
                return .{ .ready = self.pad[9999] };
            }
        };
        fn f(r: *rt.Runtime) !void {
            try testing.expectEqual(@as(u8, 1), try r.blockOn(Big, .{}));
        }
    }.f);
}

test "frames freed by one workload are reused by the next" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const n = 300_000;
            const hs = try testing.allocator.alloc(rt.JoinHandle(Leaf), n);
            defer testing.allocator.free(hs);
            try expectSum(n, try r.blockOn(Many, .{ .hs = hs }));
            var buf: [64]u32 = undefined;
            var c: Chan = .init(&buf);
            try testing.expectEqual(@as(u64, 20_000 * 19_999 / 2), try r.blockOn(FanIn, .{ .c = &c, .n = 20_000 }));
            try r.blockOn(Settle, .{});
        }
    }.f);
}

test "over-aligned tasks: frames are recycled by base address" {
    // Zig may place the header after the task in the frame; freeing must
    // still return the frame's base address to the pool.
    const Wide = struct {
        pub const Output = u64;
        x: u128,
        pub fn poll(self: *@This(), cx: *Context) Poll(u64) {
            _ = cx;
            return .{ .ready = @truncate(self.x) };
        }
    };
    const Root = struct {
        pub const Output = u64;
        hs: []rt.JoinHandle(Wide),
        spawned: bool = false,
        joined: usize = 0,
        sum: u64 = 0,
        pub fn poll(self: *@This(), cx: *Context) Poll(u64) {
            if (!self.spawned) {
                self.spawned = true;
                for (self.hs, 0..) |*h, i| h.* = cx.runtime().spawn(Wide, .{ .x = i }) catch @panic("oom");
            }
            while (self.joined < self.hs.len) : (self.joined += 1) switch (self.hs[self.joined].poll(cx)) {
                .pending => return .pending,
                .ready => |r| self.sum += r catch unreachable,
            };
            return .{ .ready = self.sum };
        }
    };
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const hs = try testing.allocator.alloc(rt.JoinHandle(Wide), 5000);
            defer testing.allocator.free(hs);
            for (0..3) |_| try testing.expectEqual(@as(u64, 5000 * 4999 / 2), try r.blockOn(Root, .{ .hs = hs }));
            var buf: [8]u32 = undefined;
            var c: Chan = .init(&buf);
            try testing.expectEqual(@as(u64, 3000 * 2999 / 2), try r.blockOn(FanIn, .{ .c = &c, .n = 3000 }));
            try r.blockOn(Settle, .{});
        }
    }.f);
}

test "docs/rt.md example" {
    const Double = struct {
        pub const Output = u64;
        v: u64,
        pub fn poll(self: *@This(), cx: *rt.Context) rt.Poll(u64) {
            _ = cx;
            return .{ .ready = self.v * 2 };
        }
    };
    const Parent = struct {
        pub const Output = u64;
        h: ?rt.JoinHandle(Double) = null,
        pub fn poll(self: *@This(), cx: *rt.Context) rt.Poll(u64) {
            if (self.h == null) self.h = cx.runtime().spawn(Double, .{ .v = 21 }) catch @panic("oom");
            return switch (self.h.?.poll(cx)) {
                .pending => .pending,
                .ready => |r| .{ .ready = r catch 0 },
            };
        }
    };
    var r: rt.Runtime = undefined;
    try r.init(testing.allocator, testing.io, .{});
    defer r.deinit();
    try testing.expectEqual(@as(u64, 42), try r.blockOn(Parent, .{}));
}

// ------------------------------------------------------ timers / driver ---

const ms = std.time.ns_per_ms;

/// Sleeps `ns` and reports how late it woke (ns past the deadline).
const SleepCheck = struct {
    pub const Output = u64;
    ns: u64,
    deadline: u64 = 0,
    timer: rt.Timer = .{},
    pub fn poll(self: *SleepCheck, cx: *Context) Poll(u64) {
        const r = cx.runtime();
        if (self.deadline == 0) self.deadline = r.now() + self.ns;
        if (self.timer.sleepUntil(cx, self.deadline) == .pending) return .pending;
        const now = r.now();
        std.debug.assert(now >= self.deadline);
        return .{ .ready = now - self.deadline };
    }
    pub fn deinit(self: *SleepCheck) void {
        _ = self.timer.cancel();
    }
};

test "timer: sleep waits at least its duration" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const t0 = r.now();
            _ = try r.blockOn(SleepCheck, .{ .ns = 5 * ms });
            try testing.expect(r.now() - t0 >= 5 * ms);
            try r.blockOn(rt.Sleep, .init(1 * ms));
        }
    }.f);
}

/// Spawns `n` sleepers with scattered deadlines and joins them all.
const ManySleeps = struct {
    pub const Output = u64;
    hs: []rt.JoinHandle(SleepCheck),
    spawned: usize = 0,
    joined: usize = 0,
    worst: u64 = 0,
    pub fn poll(self: *ManySleeps, cx: *Context) Poll(u64) {
        while (self.spawned < self.hs.len) : (self.spawned += 1) {
            const ns = (self.spawned * 7919 % 20) * ms / 4;
            self.hs[self.spawned] = cx.runtime().spawn(SleepCheck, .{ .ns = ns }) catch @panic("oom");
        }
        while (self.joined < self.hs.len) {
            switch (self.hs[self.joined].poll(cx)) {
                .pending => return .pending,
                .ready => |late| {
                    self.worst = @max(self.worst, late catch unreachable);
                    self.joined += 1;
                },
            }
        }
        return .{ .ready = self.worst };
    }
};

test "timer: thousands of timers fire, none early" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const hs = try testing.allocator.alloc(rt.JoinHandle(SleepCheck), 3000);
            defer testing.allocator.free(hs);
            for (0..3) |_| _ = try r.blockOn(ManySleeps, .{ .hs = hs });
        }
    }.f);
}

/// Counts allocations to prove the steady state allocates nothing.
const CountingAllocator = struct {
    inner: std.mem.Allocator,
    count: std.atomic.Value(usize) = .init(0),
    fn allocator(c: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = c, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(p: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const c: *CountingAllocator = @ptrCast(@alignCast(p));
        _ = c.count.fetchAdd(1, .monotonic);
        return c.inner.rawAlloc(len, a, ra);
    }
    fn resize(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const c: *CountingAllocator = @ptrCast(@alignCast(p));
        return c.inner.rawResize(m, a, n, ra);
    }
    fn remap(p: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const c: *CountingAllocator = @ptrCast(@alignCast(p));
        _ = c.count.fetchAdd(1, .monotonic);
        return c.inner.rawRemap(m, a, n, ra);
    }
    fn free(p: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const c: *CountingAllocator = @ptrCast(@alignCast(p));
        c.inner.rawFree(m, a, ra);
    }
};

/// Re-arms its own timer `n` times.
const Rearm = struct {
    pub const Output = void;
    n: u32,
    timer: rt.Timer = .{},
    pub fn poll(self: *Rearm, cx: *Context) Poll(void) {
        while (self.n > 0) {
            if (self.timer.sleep(cx, 20 * std.time.ns_per_us) == .pending) return .pending;
            self.n -= 1;
        }
        return .{ .ready = {} };
    }
};

test "timer: steady state allocates nothing" {
    var ca: CountingAllocator = .{ .inner = std.heap.smp_allocator };
    inline for (modes) |m| {
        var r: rt.Runtime = undefined;
        try r.init(ca.allocator(), testing.io, m);
        defer r.deinit();
        try r.blockOn(Rearm, .{ .n = 10 }); // starts the driver
        var before = ca.count.load(.monotonic);
        try r.blockOn(Rearm, .{ .n = 1000 });
        try testing.expectEqual(before, ca.count.load(.monotonic));
        // Many concurrent timers: frame pools settle after a few rounds
        // (frames migrate between workers), then nothing is allocated.
        const hs = try testing.allocator.alloc(rt.JoinHandle(SleepCheck), 500);
        defer testing.allocator.free(hs);
        var stable: usize = 0;
        var round: usize = 0;
        while (round < 30 and stable < 3) : (round += 1) {
            before = ca.count.load(.monotonic);
            _ = try r.blockOn(ManySleeps, .{ .hs = hs });
            try r.blockOn(Settle, .{});
            stable = if (ca.count.load(.monotonic) == before) stable + 1 else 0;
        }
        try testing.expect(stable == 3);
    }
}

const RecvTimeout = struct {
    pub const Output = error{Timeout}!?u32;
    ch: *rt.Channel(u32),
    w: rt.Channel(u32).RecvWaiter = .{},
    t: rt.Timer = .{},
    deadline: u64 = 0,
    ns: u64,
    pub fn poll(self: *RecvTimeout, cx: *Context) Poll(Output) {
        if (self.deadline == 0) self.deadline = cx.runtime().now() + self.ns;
        return self.ch.recvDeadline(cx, &self.w, &self.t, self.deadline);
    }
    pub fn deinit(self: *RecvTimeout) void {
        _ = self.t.cancel();
        self.ch.cancelRecv(&self.w);
    }
};

const DelayedSend = struct {
    pub const Output = void;
    ch: *rt.Channel(u32),
    v: u32,
    sleep: rt.Sleep = .init(2 * ms),
    w: rt.Channel(u32).SendWaiter = .{},
    pub fn poll(self: *DelayedSend, cx: *Context) Poll(void) {
        if (self.sleep.poll(cx) == .pending) return .pending;
        return switch (self.ch.send(cx, &self.w, self.v)) {
            .pending => .pending,
            .ready => .{ .ready = {} },
        };
    }
};

const TimeoutsAll = struct {
    pub const Output = void;
    ch: *rt.Channel(u32),
    sem: *rt.Semaphore,
    step: u8 = 0,
    rt1: RecvTimeout = undefined,
    jh: ?rt.JoinHandle(SleepCheck) = null,
    jt: rt.Timer = .{},
    jd: u64 = 0,
    sw: rt.Semaphore.Waiter = .{},
    st: rt.Timer = .{},
    sd: u64 = 0,
    pub fn poll(self: *TimeoutsAll, cx: *Context) Poll(void) {
        const r = cx.runtime();
        while (true) switch (self.step) {
            0 => { // nothing arrives: timeout
                self.rt1 = .{ .ch = self.ch, .ns = 1 * ms };
                self.step = 1;
            },
            1 => switch (self.rt1.poll(cx)) {
                .pending => return .pending,
                .ready => |v| {
                    std.debug.assert(v == error.Timeout);
                    r.spawnDetached(DelayedSend, .{ .ch = self.ch, .v = 42 }) catch @panic("oom");
                    self.rt1 = .{ .ch = self.ch, .ns = 5000 * ms };
                    self.step = 2;
                },
            },
            2 => switch (self.rt1.poll(cx)) { // arrives before the deadline
                .pending => return .pending,
                .ready => |v| {
                    std.debug.assert((v catch unreachable).? == 42);
                    std.debug.assert(!self.rt1.t.isArmed());
                    self.jh = r.spawn(SleepCheck, .{ .ns = 20 * ms }) catch @panic("oom");
                    self.jd = r.now() + 1 * ms;
                    self.step = 3;
                },
            },
            3 => switch (self.jh.?.pollDeadline(cx, &self.jt, self.jd)) { // join times out
                .pending => return .pending,
                .ready => |v| {
                    std.debug.assert(v == error.Timeout);
                    self.jd = r.now() + 5000 * ms;
                    self.step = 4;
                },
            },
            4 => switch (self.jh.?.pollDeadline(cx, &self.jt, self.jd)) { // then completes
                .pending => return .pending,
                .ready => |v| {
                    _ = (v catch unreachable) catch unreachable;
                    self.sd = r.now() + 1 * ms;
                    self.step = 5;
                },
            },
            5 => switch (self.sem.acquireDeadline(cx, &self.sw, &self.st, self.sd)) {
                .pending => return .pending,
                .ready => |v| {
                    std.debug.assert(v == error.Timeout);
                    std.debug.assert(self.sem.available() == 0);
                    return .{ .ready = {} };
                },
            },
            else => unreachable,
        };
    }
};

test "deadlines: channel recv, join and semaphore time out or succeed" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            var ch = rt.Channel(u32).init(&.{});
            var sem = rt.Semaphore.init(0);
            try r.blockOn(TimeoutsAll, .{ .ch = &ch, .sem = &sem });
        }
    }.f);
}

// ------------------------------------------------------------ Seq/Race ---

/// Ping-pong written with `Seq`: no hand-written state enum.
const SeqPinger = rt.Seq(struct {
    pub const Output = u64;
    pub const steps = .{ send, recv };
    to: *rt.Channel(u64),
    from: *rt.Channel(u64),
    n: u64,
    i: u64 = 0,
    got: ?u64 = null,
    sw: rt.Channel(u64).SendWaiter = .{},
    rw: rt.Channel(u64).RecvWaiter = .{},
    const C = @This();
    pub fn output(c: *C) u64 {
        return c.i;
    }
    fn send(c: *C, cx: *Context) rt.Flow {
        if (c.i == c.n) return .done;
        return switch (c.to.send(cx, &c.sw, c.i)) {
            .pending => .pending,
            .ready => .next,
        };
    }
    fn recv(c: *C, cx: *Context) rt.Flow {
        if (rt.into(?u64, c.from.recv(cx, &c.rw), &c.got) == .pending) return .pending;
        std.debug.assert(c.got.? == c.i);
        c.i += 1;
        return .{ .jump = 0 };
    }
});

const SeqPonger = rt.Seq(struct {
    pub const Output = u64;
    pub const steps = .{ recv, send };
    from: *rt.Channel(u64),
    to: *rt.Channel(u64),
    count: u64 = 0,
    v: ?u64 = null,
    sw: rt.Channel(u64).SendWaiter = .{},
    rw: rt.Channel(u64).RecvWaiter = .{},
    const C = @This();
    pub fn output(c: *C) u64 {
        return c.count;
    }
    fn recv(c: *C, cx: *Context) rt.Flow {
        if (rt.into(?u64, c.from.recv(cx, &c.rw), &c.v) == .pending) return .pending;
        return if (c.v == null) .done else .next;
    }
    fn send(c: *C, cx: *Context) rt.Flow {
        return switch (c.to.send(cx, &c.sw, c.v.?)) {
            .pending => .pending,
            .ready => blk: {
                c.count += 1;
                break :blk .{ .jump = 0 };
            },
        };
    }
});

const SeqPingPong = rt.Seq(struct {
    pub const Output = u64;
    pub const steps = .{ start, join };
    n: u64,
    a: rt.Channel(u64) = .init(&.{}),
    b: rt.Channel(u64) = .init(&.{}),
    ponger: ?rt.JoinHandle(SeqPonger) = null,
    pinger: SeqPinger = undefined,
    pongs: u64 = 0,
    const C = @This();
    pub fn output(c: *C) u64 {
        return c.pongs;
    }
    fn start(c: *C, cx: *Context) rt.Flow {
        c.ponger = cx.runtime().spawn(SeqPonger, .init(.{ .from = &c.a, .to = &c.b })) catch @panic("oom");
        c.pinger = .init(.{ .to = &c.a, .from = &c.b, .n = c.n });
        return .next;
    }
    fn join(c: *C, cx: *Context) rt.Flow {
        switch (c.pinger.poll(cx)) {
            .pending => return .pending,
            .ready => |n| std.debug.assert(n == c.n),
        }
        c.a.close();
        switch (c.ponger.?.poll(cx)) {
            .pending => return .pending,
            .ready => |r| c.pongs = r catch unreachable,
        }
        return .next;
    }
});

test "Seq: ping-pong without a hand-written state machine" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            // The frame owns both channels; it must outlive the ponger, which
            // the join step guarantees.
            try testing.expectEqual(@as(u64, 10_000), try r.blockOn(SeqPingPong, .init(.{ .n = 10_000 })));
        }
    }.f);
}

/// Never ready (until aborted).
const Forever = struct {
    pub const Output = u32;
    pub fn poll(_: *Forever, _: *Context) Poll(u32) {
        return .pending;
    }
};

test "Race: timeout wins over a task that never finishes; All waits for both" {
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const R = rt.Race(Forever, rt.Sleep);
            const o = try r.blockOn(R, .init(.{}, .init(2 * ms)));
            try testing.expect(o == .b);
            const A = rt.All(rt.Sleep, SleepCheck);
            const t0 = r.now();
            _ = try r.blockOn(A, .init(.init(3 * ms), .{ .ns = 1 * ms }));
            try testing.expect(r.now() - t0 >= 3 * ms);
        }
    }.f);
}

// ------------------------------------------------------------ reactor ---

fn makePipe() ![2]std.posix.fd_t {
    var fds: [2]std.posix.fd_t = undefined;
    if (std.posix.errno(std.posix.system.pipe(&fds)) != .SUCCESS) return error.Pipe;
    return fds;
}

fn closeFd(fd: std.posix.fd_t) void {
    _ = std.posix.system.close(fd);
}

const pipe_bytes = 1 << 20;

const PipeWriter = struct {
    pub const Output = usize;
    src: *rt.IoSource,
    sent: usize = 0,
    buf: [4096]u8 = undefined,
    pub fn poll(self: *PipeWriter, cx: *Context) Poll(usize) {
        while (self.sent < pipe_bytes) {
            for (&self.buf, 0..) |*b, i| b.* = @truncate(self.sent + i);
            const want = @min(self.buf.len, pipe_bytes - self.sent);
            switch (self.src.write(cx, self.buf[0..want])) {
                .pending => return .pending,
                .ready => |n| self.sent += n catch @panic("write"),
            }
        }
        return .{ .ready = self.sent };
    }
    pub fn deinit(self: *PipeWriter) void {
        closeFd(self.src.fd);
    }
};

const PipeReader = struct {
    pub const Output = usize;
    src: *rt.IoSource,
    got: usize = 0,
    buf: [3000]u8 = undefined,
    pub fn poll(self: *PipeReader, cx: *Context) Poll(usize) {
        while (true) {
            switch (self.src.read(cx, &self.buf)) {
                .pending => return .pending,
                .ready => |res| {
                    const n = res catch @panic("read");
                    if (n == 0) return .{ .ready = self.got };
                    for (self.buf[0..n], 0..) |b, i| std.debug.assert(b == @as(u8, @truncate(self.got + i)));
                    self.got += n;
                },
            }
        }
    }
};

const PipeBoth = struct {
    pub const Output = usize;
    rd: *rt.IoSource,
    wr: *rt.IoSource,
    w: ?rt.JoinHandle(PipeWriter) = null,
    reader: PipeReader = undefined,
    got: usize = 0,
    pub fn poll(self: *PipeBoth, cx: *Context) Poll(usize) {
        if (self.w == null) {
            self.w = cx.runtime().spawn(PipeWriter, .{ .src = self.wr }) catch @panic("oom");
            self.reader = .{ .src = self.rd };
        }
        if (self.got == 0) switch (self.reader.poll(cx)) {
            .pending => return .pending,
            .ready => |n| self.got = n,
        };
        return switch (self.w.?.poll(cx)) {
            .pending => .pending,
            .ready => |n| blk: {
                std.debug.assert((n catch unreachable) == pipe_bytes);
                break :blk .{ .ready = self.got };
            },
        };
    }
};

test "reactor: 1 MiB through a non-blocking pipe" {
    if (!rt.reactor_available) return error.SkipZigTest;
    inline for (modes) |m| try withRuntime(m, struct {
        fn f(r: *rt.Runtime) !void {
            const fds = try makePipe();
            var rd: rt.IoSource = .{};
            var wr: rt.IoSource = .{};
            try rd.register(r, fds[0]);
            try wr.register(r, fds[1]);
            defer {
                rd.deregister();
                wr.deregister();
                closeFd(fds[0]);
            }
            try testing.expectEqual(@as(usize, pipe_bytes), try r.blockOn(PipeBoth, .{ .rd = &rd, .wr = &wr }));
        }
    }.f);
}

const ReadFileTask = struct {
    pub const Output = usize;
    fd: std.posix.fd_t,
    buf: []u8,
    op: rt.FileRead = .{},
    pub fn poll(self: *ReadFileTask, cx: *Context) Poll(usize) {
        return switch (self.op.poll(cx, .{ .fd = self.fd, .buf = self.buf, .offset = 3 })) {
            .pending => .pending,
            .ready => |n| .{ .ready = n catch @panic("pread") },
        };
    }
};

test "blocking pool: positional file read" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "f.txt", .data = "0123456789" });
    var file = try tmp.dir.openFile(testing.io, "f.txt", .{});
    defer file.close(testing.io);
    inline for (modes) |m| {
        var r: rt.Runtime = undefined;
        try r.init(testing.allocator, testing.io, m);
        defer r.deinit();
        var buf: [4]u8 = undefined;
        try testing.expectEqual(@as(usize, 4), try r.blockOn(ReadFileTask, .{ .fd = file.handle, .buf = &buf }));
        try testing.expectEqualStrings("3456", &buf);
    }
}

// ------------------------------------------------------------ monitor ---

const Flag = struct {
    pub const Output = void;
    flag: *std.atomic.Value(bool),
    pub fn poll(self: *Flag, _: *Context) Poll(void) {
        self.flag.store(true, .release);
        return .{ .ready = {} };
    }
};

/// Pushes work onto the unpublished queue tail, then blocks this worker in a
/// long poll until that work ran on the other worker (the monitor publishes
/// the tail). The LIFO slot stays local and is not stolen.
const Hog = struct {
    pub const Output = bool;
    flag: std.atomic.Value(bool) = .init(false),
    step: u8 = 0,
    pub fn poll(self: *Hog, cx: *Context) Poll(bool) {
        const r = cx.runtime();
        if (self.step == 0) {
            self.step = 1;
            r.spawnDetached(Flag, .{ .flag = &self.flag }) catch @panic("oom");
        }
        const t0 = r.now();
        while (!self.flag.load(.acquire)) {
            if (r.now() - t0 > 3 * std.time.ns_per_s) return .{ .ready = false };
            std.atomic.spinLoopHint();
        }
        return .{ .ready = true };
    }
};

test "monitor: work held by a worker stuck in a long poll is stolen" {
    var r: rt.Runtime = undefined;
    try r.init(testing.allocator, testing.io, .{ .workers = 2 });
    defer r.deinit();
    // The driver (and therefore the monitor) starts on first timer / IoSource,
    // not in init. Start it here so unpublished work can be published remotely.
    try r.driver().ensureStarted();
    for (0..5) |_| {
        try testing.expect(try r.blockOn(Hog, .{}));
    }
    try r.blockOn(Settle, .{});
    try testing.expect(r.monitorRescues() > 0);
}
