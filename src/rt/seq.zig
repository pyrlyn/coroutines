//! Writing tasks without hand-written state machines.
//!
//! `Seq` turns a list of step functions into a task. Each step gets the
//! task's context struct and returns a `Flow`: wait (`.pending`), go to the
//! next step, jump to another step (loops), or finish. The step list is
//! comptime, so `poll` is an `inline` switch over the program counter: the
//! same code a hand-written `switch (state)` compiles to, with no function
//! pointers and no allocation. What it cannot do is keep locals across a
//! wait; they live in the context struct, exactly as in a hand-written task
//! (that is the price of stackless tasks; stackful coroutines would keep a
//! stack per task instead).
//!
//! `Race(A, B)` / `All(A, B)` run two tasks inline in one task (no spawn);
//! `Sleep` is a task that waits; `Race(T, Sleep)` is a timeout.
const std = @import("std");
const rt = @import("../rt.zig");

pub const Flow = union(enum) {
    /// Waiting: poll this step again when woken.
    pending,
    /// Step done: continue with the next one (finish after the last).
    next,
    /// Continue with step `jump` (0-based).
    jump: u8,
    /// Finish now.
    done,
};

/// Stores a ready value in `dest` and continues with the next step.
pub fn into(comptime T: type, p: rt.Poll(T), dest: *T) Flow {
    switch (p) {
        .pending => return .pending,
        .ready => |v| {
            dest.* = v;
            return .next;
        },
    }
}

/// A task running `Ctx.steps` (a tuple of `fn (*Ctx, *rt.Context) Flow`)
/// in order. `Ctx` declares `pub const Output`, `pub const steps` and
/// `pub fn output(*Ctx) Output`, and may declare `deinit`.
pub fn Seq(comptime Ctx: type) type {
    const steps = Ctx.steps;
    const n = steps.len;
    comptime std.debug.assert(n > 0 and n <= 255);
    return struct {
        const Self = @This();
        pub const Output = Ctx.Output;
        ctx: Ctx,
        pc: u8 = 0,

        pub fn init(ctx: Ctx) Self {
            return .{ .ctx = ctx };
        }

        pub fn poll(self: *Self, cx: *rt.Context) rt.Poll(Output) {
            while (true) {
                const f: Flow = switch (self.pc) {
                    inline 0...n - 1 => |i| steps[i](&self.ctx, cx),
                    else => unreachable,
                };
                switch (f) {
                    .pending => return .pending,
                    .next => {
                        self.pc += 1;
                        if (self.pc == n) return .{ .ready = self.ctx.output() };
                    },
                    .jump => |j| self.pc = j,
                    .done => return .{ .ready = self.ctx.output() },
                }
            }
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(Ctx, "deinit")) self.ctx.deinit();
        }
    };
}

fn deinitTask(comptime T: type, t: *T) void {
    if (@hasDecl(T, "deinit")) t.deinit();
}

/// Polls `a` and `b` in the same task; ready with the first to finish. The
/// loser is dropped (its `deinit` runs) at once. Used inside another task,
/// call `deinit` if the race is abandoned before it finishes.
pub fn Race(comptime A: type, comptime B: type) type {
    return struct {
        const Self = @This();
        pub const Output = union(enum) { a: A.Output, b: B.Output };
        a: A,
        b: B,
        over: bool = false,

        pub fn init(a: A, b: B) Self {
            return .{ .a = a, .b = b };
        }

        pub fn poll(self: *Self, cx: *rt.Context) rt.Poll(Output) {
            switch (self.a.poll(cx)) {
                .ready => |v| return self.win(.{ .a = v }),
                .pending => {},
            }
            switch (self.b.poll(cx)) {
                .ready => |v| return self.win(.{ .b = v }),
                .pending => return .pending,
            }
        }

        fn win(self: *Self, o: Output) rt.Poll(Output) {
            self.over = true;
            deinitTask(A, &self.a);
            deinitTask(B, &self.b);
            return .{ .ready = o };
        }

        pub fn deinit(self: *Self) void {
            if (self.over) return;
            self.over = true;
            deinitTask(A, &self.a);
            deinitTask(B, &self.b);
        }
    };
}

/// Polls `a` and `b` in the same task until both are ready.
pub fn All(comptime A: type, comptime B: type) type {
    return struct {
        const Self = @This();
        pub const Output = struct { a: A.Output, b: B.Output };
        a: A,
        b: B,
        ra: ?A.Output = null,
        rb: ?B.Output = null,
        over: bool = false,

        pub fn init(a: A, b: B) Self {
            return .{ .a = a, .b = b };
        }

        pub fn poll(self: *Self, cx: *rt.Context) rt.Poll(Output) {
            if (self.ra == null) switch (self.a.poll(cx)) {
                .ready => |v| self.ra = v,
                .pending => {},
            };
            if (self.rb == null) switch (self.b.poll(cx)) {
                .ready => |v| self.rb = v,
                .pending => {},
            };
            if (self.ra == null or self.rb == null) return .pending;
            self.deinit();
            return .{ .ready = .{ .a = self.ra.?, .b = self.rb.? } };
        }

        pub fn deinit(self: *Self) void {
            if (self.over) return;
            self.over = true;
            deinitTask(A, &self.a);
            deinitTask(B, &self.b);
        }
    };
}

/// A task that is ready `ns` nanoseconds after its first poll.
pub const Sleep = struct {
    pub const Output = void;
    ns: u64,
    timer: rt.Timer = .{},

    pub fn init(ns: u64) Sleep {
        return .{ .ns = ns };
    }

    pub fn poll(self: *Sleep, cx: *rt.Context) rt.Poll(void) {
        return self.timer.sleep(cx, self.ns);
    }

    pub fn deinit(self: *Sleep) void {
        _ = self.timer.cancel();
    }
};
