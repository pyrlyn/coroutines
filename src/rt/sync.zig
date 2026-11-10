//! Waiting primitives for `rt` tasks: `Channel` (bounded MPMC with direct
//! handoff) and `Semaphore` (FIFO, permits handed straight to waiters).
//!
//! Waiters are intrusive: the task keeps a `Waiter` in its own struct and
//! passes it on every poll, so waiting allocates nothing. A task that may be
//! aborted while waiting must call `cancel*` for its waiter in `deinit`.
//! Wake-ups happen under the primitive's lock, which is what keeps a woken
//! task alive until the waker is done with it.
const std = @import("std");
const rt = @import("../rt.zig");
const Context = rt.Context;
const Header = rt.Header;
const Poll = rt.Poll;

/// Short critical sections only: spin, then yield the thread.
pub const SpinLock = struct {
    state: std.atomic.Value(u32) = .init(0),

    pub fn lock(l: *SpinLock) void {
        if (l.state.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) return;
        l.lockSlow();
    }
    fn lockSlow(l: *SpinLock) void {
        @branchHint(.cold);
        var backoff: u32 = 1;
        var rounds: u32 = 0;
        while (true) {
            while (l.state.load(.monotonic) != 0) {
                if (rounds < 64) {
                    for (0..backoff) |_| std.atomic.spinLoopHint();
                    if (backoff < 64) backoff *= 2;
                    rounds += 1;
                } else std.Thread.yield() catch {};
            }
            if (l.state.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) return;
        }
    }
    pub fn tryLock(l: *SpinLock) bool {
        return l.state.load(.monotonic) == 0 and l.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null;
    }
    pub fn unlock(l: *SpinLock) void {
        l.state.store(0, .release);
    }
};

/// Intrusive doubly linked FIFO.
fn List(comptime Node: type) type {
    return struct {
        const Self = @This();
        head: ?*Node = null,
        tail: ?*Node = null,

        fn pushBack(l: *Self, n: *Node) void {
            n.next = null;
            n.prev = l.tail;
            if (l.tail) |t| t.next = n else l.head = n;
            l.tail = n;
        }
        fn popFront(l: *Self) ?*Node {
            const n = l.head orelse return null;
            l.remove(n);
            return n;
        }
        fn remove(l: *Self, n: *Node) void {
            if (n.prev) |p| p.next = n.next else l.head = n.next;
            if (n.next) |x| x.prev = n.prev else l.tail = n.prev;
            n.next = null;
            n.prev = null;
        }
    };
}

pub const WaitState = enum(u8) { idle, waiting, done, closed };

/// Completes a waiter that was just unlinked (under the lock): wake the task
/// first, then publish the state. Once the state is published the task may
/// finish without the lock, so the waiter must not be touched afterwards.
fn finish(w: anytype, state: WaitState) void {
    rt.wakeHeader(w.task.?);
    @atomicStore(WaitState, &w.state, state, .release);
}

/// Lock-free check of a waiter that has been completed.
inline fn finished(w: anytype) WaitState {
    return @atomicLoad(WaitState, &w.state, .acquire);
}

/// Bounded multi-producer multi-consumer channel. `buf` is caller storage;
/// `buf.len == 0` makes a rendezvous channel. A send to a waiting receiver
/// hands the value over directly and wakes it into the sender's worker LIFO
/// slot. A full channel parks senders (backpressure) without a thread.
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        lock: SpinLock = .{},
        buf: []T,
        head: usize = 0,
        len: usize = 0,
        closed: bool = false,
        receivers: List(RecvWaiter) = .{},
        senders: List(SendWaiter) = .{},

        pub const RecvWaiter = struct {
            next: ?*RecvWaiter = null,
            prev: ?*RecvWaiter = null,
            task: ?*Header = null,
            state: WaitState = .idle,
            value: T = undefined,
        };
        pub const SendWaiter = struct {
            next: ?*SendWaiter = null,
            prev: ?*SendWaiter = null,
            task: ?*Header = null,
            state: WaitState = .idle,
            value: T = undefined,
        };

        pub fn init(buf: []T) Self {
            return .{ .buf = buf };
        }

        /// Sends `v`. While `.pending`, poll again with the same waiter (the
        /// value is already stored in it; `v` is ignored).
        pub fn send(c: *Self, cx: *Context, w: *SendWaiter, v: T) Poll(error{Closed}!void) {
            switch (finished(w)) {
                .done => {
                    w.state = .idle;
                    return .{ .ready = {} };
                },
                .closed => {
                    w.state = .idle;
                    return .{ .ready = error.Closed };
                },
                else => {},
            }
            c.lock.lock();
            defer c.lock.unlock();
            switch (w.state) {
                .done => {
                    w.state = .idle;
                    return .{ .ready = {} };
                },
                .waiting => return .pending,
                .closed => {
                    w.state = .idle;
                    return .{ .ready = error.Closed };
                },
                .idle => {},
            }
            if (c.closed) return .{ .ready = error.Closed };
            if (c.pushLocked(v)) return .{ .ready = {} };
            w.value = v;
            w.task = cx.header;
            w.state = .waiting;
            c.senders.pushBack(w);
            return .pending;
        }

        /// Receives a value; `null` once the channel is closed and drained.
        pub fn recv(c: *Self, cx: *Context, w: *RecvWaiter) Poll(?T) {
            switch (finished(w)) {
                .done => {
                    w.state = .idle;
                    return .{ .ready = w.value };
                },
                .closed => {
                    w.state = .idle;
                    return .{ .ready = null };
                },
                else => {},
            }
            c.lock.lock();
            defer c.lock.unlock();
            switch (w.state) {
                .done => {
                    w.state = .idle;
                    return .{ .ready = w.value };
                },
                .waiting => return .pending,
                .closed => {
                    w.state = .idle;
                    return .{ .ready = null };
                },
                .idle => {},
            }
            if (c.popLocked()) |v| return .{ .ready = v };
            if (c.closed) return .{ .ready = null };
            w.task = cx.header;
            w.state = .waiting;
            c.receivers.pushBack(w);
            return .pending;
        }

        /// Never waits. `error.Full` when there is neither room nor a receiver.
        pub fn trySend(c: *Self, v: T) error{ Closed, Full }!void {
            c.lock.lock();
            defer c.lock.unlock();
            if (c.closed) return error.Closed;
            if (!c.pushLocked(v)) return error.Full;
        }

        /// Never waits. `error.Empty` or `error.Closed` (closed and drained).
        pub fn tryRecv(c: *Self) error{ Closed, Empty }!T {
            c.lock.lock();
            defer c.lock.unlock();
            if (c.popLocked()) |v| return v;
            return if (c.closed) error.Closed else error.Empty;
        }

        fn pushLocked(c: *Self, v: T) bool {
            if (c.receivers.popFront()) |r| {
                r.value = v;
                finish(r, .done);
                return true;
            }
            if (c.len < c.buf.len) {
                c.buf[(c.head + c.len) % c.buf.len] = v;
                c.len += 1;
                return true;
            }
            return false;
        }

        fn popLocked(c: *Self) ?T {
            if (c.len > 0) {
                const v = c.buf[c.head];
                c.head = (c.head + 1) % c.buf.len;
                c.len -= 1;
                if (c.senders.popFront()) |s| {
                    c.buf[(c.head + c.len) % c.buf.len] = s.value;
                    c.len += 1;
                    finish(s, .done);
                }
                return v;
            }
            if (c.senders.popFront()) |s| { // rendezvous
                const v = s.value;
                finish(s, .done);
                return v;
            }
            return null;
        }

        /// Wakes every waiter: receivers get `null` after the buffer drains,
        /// senders get `error.Closed`.
        pub fn close(c: *Self) void {
            c.lock.lock();
            defer c.lock.unlock();
            c.closed = true;
            while (c.receivers.popFront()) |r| {
                finish(r, .closed);
            }
            while (c.senders.popFront()) |s| {
                finish(s, .closed);
            }
        }

        /// Withdraws a waiting receiver (call from the task's `deinit`). A
        /// value already handed to it is put back at the front.
        pub fn cancelRecv(c: *Self, w: *RecvWaiter) void {
            c.lock.lock();
            defer c.lock.unlock();
            switch (w.state) {
                .waiting => c.receivers.remove(w),
                .done => _ = c.pushFrontLocked(w.value),
                else => {},
            }
            w.state = .idle;
        }

        /// Withdraws a waiting sender; its value is not sent.
        pub fn cancelSend(c: *Self, w: *SendWaiter) void {
            c.lock.lock();
            defer c.lock.unlock();
            if (w.state == .waiting) c.senders.remove(w);
            w.state = .idle;
        }

        fn pushFrontLocked(c: *Self, v: T) bool {
            if (c.receivers.popFront()) |r| {
                r.value = v;
                finish(r, .done);
                return true;
            }
            if (c.len < c.buf.len) {
                c.head = (c.head + c.buf.len - 1) % c.buf.len;
                c.buf[c.head] = v;
                c.len += 1;
                return true;
            }
            return false; // full: the value is dropped
        }
    };
}

/// Counting semaphore for tasks: concurrency limits and backpressure. FIFO:
/// `release` hands the permit straight to the oldest waiter, so a newcomer
/// can never overtake a waiting task.
pub const Semaphore = struct {
    lock: SpinLock = .{},
    permits: usize,
    waiters: List(Waiter) = .{},

    pub const Waiter = struct {
        next: ?*Waiter = null,
        prev: ?*Waiter = null,
        task: ?*Header = null,
        state: WaitState = .idle,
    };

    pub fn init(permits: usize) Semaphore {
        return .{ .permits = permits };
    }

    pub fn acquire(s: *Semaphore, cx: *Context, w: *Waiter) Poll(void) {
        if (finished(w) == .done) {
            w.state = .idle;
            return .{ .ready = {} };
        }
        s.lock.lock();
        defer s.lock.unlock();
        switch (w.state) {
            .done => {
                w.state = .idle;
                return .{ .ready = {} };
            },
            .waiting => return .pending,
            else => {},
        }
        if (s.waiters.head == null and s.permits > 0) {
            s.permits -= 1;
            return .{ .ready = {} };
        }
        w.task = cx.header;
        w.state = .waiting;
        s.waiters.pushBack(w);
        return .pending;
    }

    pub fn tryAcquire(s: *Semaphore) bool {
        s.lock.lock();
        defer s.lock.unlock();
        if (s.waiters.head == null and s.permits > 0) {
            s.permits -= 1;
            return true;
        }
        return false;
    }

    pub fn release(s: *Semaphore) void {
        s.lock.lock();
        defer s.lock.unlock();
        s.releaseLocked();
    }

    fn releaseLocked(s: *Semaphore) void {
        if (s.waiters.popFront()) |w| {
            finish(w, .done);
        } else s.permits += 1;
    }

    /// Withdraws a waiter (call from `deinit`); a permit already granted to
    /// it is passed on.
    pub fn cancel(s: *Semaphore, w: *Waiter) void {
        s.lock.lock();
        defer s.lock.unlock();
        switch (w.state) {
            .waiting => s.waiters.remove(w),
            .done => s.releaseLocked(),
            else => {},
        }
        w.state = .idle;
    }

    pub fn available(s: *Semaphore) usize {
        s.lock.lock();
        defer s.lock.unlock();
        return s.permits;
    }
};
