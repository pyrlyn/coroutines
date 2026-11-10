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
