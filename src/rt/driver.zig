//! The runtime's driver thread: timers, I/O readiness, the blocking pool and
//! the stuck-worker monitor.
//!
//! * Timers live in an intrusive pairing heap (exact earliest deadline, O(1)
//!   insert, O(log n) amortised removal); a `Timer` is embedded in the task,
//!   so arming one allocates nothing.
//! * I/O: `kqueue` on macOS / BSD, `epoll` (edge-triggered) on Linux. The
//!   driver sleeps in the poller until the next deadline; a new earlier
//!   deadline or shutdown pokes it (`EVFILT_USER` / `eventfd`). Windows has no
//!   reactor here (no IOCP yet): the driver sleeps on a futex with a timeout,
//!   so timers and the blocking pool work, sockets do not.
//! * The monitor: while any worker is busy, every `monitor_interval_ns` the
//!   driver checks whether a worker has been inside one poll for a whole
//!   interval while holding a task nobody else can see (its LIFO slot or
//!   unpublished queue tail). Such a worker is marked stuck and a parked
//!   worker is woken to steal from it.
const std = @import("std");
const builtin = @import("builtin");
const rt = @import("../rt.zig");
const sync = @import("sync.zig");
const Header = rt.Header;
const Io = std.Io;

const os = builtin.os.tag;
pub const has_kqueue = switch (os) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};
pub const has_epoll = os == .linux;
/// Whether `IoSource` (socket / pipe readiness) is available on this OS.
pub const reactor_available = has_kqueue or has_epoll;

pub fn nowNs(io: Io) u64 {
    const t = Io.Timestamp.now(io, .awake).toNanoseconds();
    return @intCast(@max(t, 0));
}

// ---------------------------------------------------------------- timers ---

/// A one-shot timer embedded in a task. Arm it with `Timer.sleepUntil`
/// (or the `*Deadline` helpers of `Channel`, `Semaphore`, `JoinHandle`).
/// A task that finishes or is aborted with an armed timer must `cancel` it
/// (the helpers do so themselves).
pub const Timer = struct {
    child: ?*Timer = null,
    sibling: ?*Timer = null,
    prev: ?*Timer = null,
    deadline: u64 = 0,
    task: ?*Header = null,
    state: sync.WaitState = .idle,

    /// Ready once `deadline` (ns on the runtime's awake clock, see
    /// `Runtime.now`) has passed.
    pub fn sleepUntil(t: *Timer, cx: *rt.Context, deadline: u64) rt.Poll(void) {
        if (@atomicLoad(sync.WaitState, &t.state, .acquire) == .done) {
            t.state = .idle;
            return .{ .ready = {} };
        }
        const r = cx.runtime();
        const d = r.driver();
        d.lock.lock();
        switch (t.state) {
            .done => {
                t.state = .idle;
                d.lock.unlock();
                return .{ .ready = {} };
            },
            .waiting => {
                d.lock.unlock();
                return .pending;
            },
            else => {},
        }
        if (deadline <= nowNs(r.io)) {
            d.lock.unlock();
            return .{ .ready = {} };
        }
        t.* = .{ .deadline = deadline, .task = cx.header, .state = .waiting };
        const earliest = d.insertLocked(t);
        d.lock.unlock();
        if (earliest) d.poke();
        return .pending;
    }

    /// Ready `ns` nanoseconds after the first poll.
    pub fn sleep(t: *Timer, cx: *rt.Context, ns: u64) rt.Poll(void) {
        const deadline = if (t.state == .idle) nowNs(cx.runtime().io) +| ns else t.deadline;
        return t.sleepUntil(cx, deadline);
    }

    /// Disarms the timer. Returns true if it had already fired.
    pub fn cancel(t: *Timer) bool {
        if (t.state == .idle) return false;
        const d = t.task.?.rt.driver();
        d.lock.lock();
        defer d.lock.unlock();
        const fired = t.state == .done;
        if (t.state == .waiting) d.removeLocked(t);
        t.state = .idle;
        return fired;
    }

    pub fn isArmed(t: *const Timer) bool {
        return @atomicLoad(sync.WaitState, &t.state, .acquire) == .waiting;
    }
};

fn meld(a: *Timer, b: *Timer) *Timer {
    var x = a;
    var y = b;
    if (y.deadline < x.deadline) std.mem.swap(*Timer, &x, &y);
    y.prev = x;
    y.sibling = x.child;
    if (x.child) |c| c.prev = y;
    x.child = y;
    return x;
}

fn mergePairs(first: ?*Timer) ?*Timer {
    var stack: ?*Timer = null;
    var it = first;
    while (it) |a| {
        const b = a.sibling orelse {
            a.prev = null;
            a.sibling = stack;
            stack = a;
            break;
        };
        const next = b.sibling;
        a.sibling = null;
        a.prev = null;
        b.sibling = null;
        b.prev = null;
        const m = meld(a, b);
        m.sibling = stack;
        stack = m;
        it = next;
    }
    var res = stack orelse return null;
    var rest = res.sibling;
    res.sibling = null;
    while (rest) |x| {
        const nx = x.sibling;
        x.sibling = null;
        res = meld(res, x);
        rest = nx;
    }
    res.prev = null;
    return res;
}

// ------------------------------------------------------------------- I/O ---

pub const fd_t = std.posix.fd_t;

const READABLE: u8 = 1;
const WRITABLE: u8 = 2;
const HUP: u8 = 4;

/// A file descriptor registered with the reactor (non-blocking sockets,
/// pipes, ttys). Embed it in a task or in shared state; it must not move
/// while registered.
pub const IoSource = struct {
    fd: fd_t = if (os == .windows) undefined else -1,
    lock: sync.SpinLock = .{},
    ready: u8 = 0,
    read_task: ?*Header = null,
    write_task: ?*Header = null,
    rt: ?*rt.Runtime = null,

    pub const Error = error{ Unsupported, SystemResources, Unexpected };

    /// Puts `fd` in non-blocking mode and registers it (edge-triggered).
    pub fn register(s: *IoSource, r: *rt.Runtime, fd: fd_t) Error!void {
        if (!reactor_available) return error.Unsupported;
        s.* = .{ .fd = fd, .rt = r };
        try setNonBlocking(fd);
        try r.driver().add(s);
    }

    /// Removes the fd from the reactor (the fd stays open). Waits until the
    /// driver can no longer deliver an event for it, so `s` may be freed
    /// afterwards. Tasks still waiting on `s` must be gone or woken first.
    pub fn deregister(s: *IoSource) void {
        if (!reactor_available) return;
        const r = s.rt orelse return;
        r.driver().remove(s);
        s.rt = null;
    }

    /// Ready when the fd is readable (or hung up). Edge-triggered: call only
    /// after a read returned `WouldBlock`.
    pub fn readable(s: *IoSource, cx: *rt.Context) rt.Poll(void) {
        return s.wait(cx, READABLE, &s.read_task);
    }
    pub fn writable(s: *IoSource, cx: *rt.Context) rt.Poll(void) {
        return s.wait(cx, WRITABLE, &s.write_task);
    }

    fn wait(s: *IoSource, cx: *rt.Context, bit: u8, slot: *?*Header) rt.Poll(void) {
        s.lock.lock();
        defer s.lock.unlock();
        if (s.ready & (bit | HUP) != 0) {
            s.ready &= ~bit;
            slot.* = null;
            return .{ .ready = {} };
        }
        slot.* = cx.header;
        return .pending;
    }

    /// Withdraws waiting tasks (call from a task's `deinit`).
    pub fn cancelWaits(s: *IoSource, cx_task: *Header) void {
        s.lock.lock();
        defer s.lock.unlock();
        if (s.read_task == cx_task) s.read_task = null;
        if (s.write_task == cx_task) s.write_task = null;
    }

    /// Non-blocking read; waits for readiness on `WouldBlock`. 0 = EOF.
    pub fn read(s: *IoSource, cx: *rt.Context, buf: []u8) rt.Poll(std.posix.ReadError!usize) {
        while (true) {
            const n = std.posix.read(s.fd, buf) catch |e| switch (e) {
                error.WouldBlock => switch (s.readable(cx)) {
                    .pending => return .pending,
                    .ready => continue,
                },
                else => return .{ .ready = e },
            };
            return .{ .ready = n };
        }
    }

    /// Non-blocking write of as much of `buf` as fits; waits on `WouldBlock`.
    pub fn write(s: *IoSource, cx: *rt.Context, buf: []const u8) rt.Poll(WriteError!usize) {
        while (true) {
            const n = sysWrite(s.fd, buf) catch |e| switch (e) {
                error.WouldBlock => switch (s.writable(cx)) {
                    .pending => return .pending,
                    .ready => continue,
                },
                else => return .{ .ready = e },
            };
            return .{ .ready = n };
        }
    }

    fn onEvent(s: *IoSource, bits: u8) void {
        s.lock.lock();
        defer s.lock.unlock();
        s.ready |= bits;
        if (bits & (READABLE | HUP) != 0) if (s.read_task) |t| {
            s.read_task = null;
            rt.wakeHeader(t);
        };
        if (bits & (WRITABLE | HUP) != 0) if (s.write_task) |t| {
            s.write_task = null;
            rt.wakeHeader(t);
        };
    }
};

pub const WriteError = error{ WouldBlock, BrokenPipe, Unexpected };

fn sysWrite(fd: fd_t, buf: []const u8) WriteError!usize {
    if (os == .windows) return error.Unexpected;
    while (true) {
        const rc = std.posix.system.write(fd, buf.ptr, buf.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .AGAIN => return error.WouldBlock,
            .PIPE => return error.BrokenPipe,
            else => return error.Unexpected,
        }
    }
}

fn setNonBlocking(fd: fd_t) IoSource.Error!void {
    if (os == .windows) return error.Unsupported;
    const sys = std.posix.system;
    const fl = sys.fcntl(fd, std.posix.F.GETFL, @as(usize, 0));
    if (std.posix.errno(fl) != .SUCCESS) return error.Unexpected;
    const OInt = @Int(.unsigned, @bitSizeOf(std.posix.O));
    const cur: OInt = @truncate(@as(usize, @intCast(fl)));
    const nb: OInt = @bitCast(std.posix.O{ .NONBLOCK = true });
    const rc = sys.fcntl(fd, std.posix.F.SETFL, @as(usize, cur | nb));
    if (std.posix.errno(rc) != .SUCCESS) return error.Unexpected;
}

// kqueue constants not exported by std.
const EV_ADD: u16 = 0x0001;
const EV_DELETE: u16 = 0x0002;
const EV_CLEAR: u16 = 0x0020;
const EV_EOF: u16 = 0x8000;
const EV_ERROR: u16 = 0x4000;
const EV_RECEIPT: u16 = 0x0040;
const NOTE_TRIGGER: u32 = 0x01000000;
const user_ident: usize = 0x5254; // "RT"

const Poller = if (has_kqueue) struct {
    kq: c_int = -1,
    fn init(p: *@This()) !void {
        p.kq = std.c.kqueue();
        if (p.kq < 0) return error.SystemResources;
        var ev = [1]std.c.Kevent{.{ .ident = user_ident, .filter = std.c.EVFILT.USER, .flags = EV_ADD | EV_CLEAR, .fflags = 0, .data = 0, .udata = 0 }};
        if (std.c.kevent(p.kq, &ev, 1, &ev, 0, null) < 0) return error.SystemResources;
    }
    fn deinit(p: *@This()) void {
        _ = std.c.close(p.kq);
    }
    fn poke(p: *@This()) void {
        var ev = [1]std.c.Kevent{.{ .ident = user_ident, .filter = std.c.EVFILT.USER, .flags = 0, .fflags = NOTE_TRIGGER, .data = 0, .udata = 0 }};
        _ = std.c.kevent(p.kq, &ev, 1, &ev, 0, null);
    }
    fn add(p: *@This(), s: *IoSource) !void {
        var ch = [2]std.c.Kevent{
            .{ .ident = @intCast(s.fd), .filter = std.c.EVFILT.READ, .flags = EV_ADD | EV_CLEAR | EV_RECEIPT, .fflags = 0, .data = 0, .udata = @intFromPtr(s) },
            .{ .ident = @intCast(s.fd), .filter = std.c.EVFILT.WRITE, .flags = EV_ADD | EV_CLEAR | EV_RECEIPT, .fflags = 0, .data = 0, .udata = @intFromPtr(s) },
        };
        var out: [2]std.c.Kevent = undefined;
        if (std.c.kevent(p.kq, &ch, 2, &out, 2, null) < 0) return error.SystemResources;
    }
    fn remove(p: *@This(), s: *IoSource) void {
        var ch = [2]std.c.Kevent{
            .{ .ident = @intCast(s.fd), .filter = std.c.EVFILT.READ, .flags = EV_DELETE | EV_RECEIPT, .fflags = 0, .data = 0, .udata = 0 },
            .{ .ident = @intCast(s.fd), .filter = std.c.EVFILT.WRITE, .flags = EV_DELETE | EV_RECEIPT, .fflags = 0, .data = 0, .udata = 0 },
        };
        var out: [2]std.c.Kevent = undefined;
        _ = std.c.kevent(p.kq, &ch, 2, &out, 2, null);
    }
    /// Waits up to `timeout_ns` (null = forever); dispatches events.
    fn wait(p: *@This(), timeout_ns: ?u64) void {
        var evs: [64]std.c.Kevent = undefined;
        var ts: std.c.timespec = undefined;
        const tsp: ?*const std.c.timespec = if (timeout_ns) |ns| blk: {
            ts = .{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
            break :blk &ts;
        } else null;
        const n = std.c.kevent(p.kq, &evs, 0, &evs, evs.len, tsp);
        if (n <= 0) return;
        for (evs[0..@intCast(n)]) |e| {
            if (e.filter == std.c.EVFILT.USER or e.udata == 0) continue;
            const s: *IoSource = @ptrFromInt(e.udata);
            var bits: u8 = if (e.filter == std.c.EVFILT.READ) READABLE else WRITABLE;
            if (e.flags & (EV_EOF | EV_ERROR) != 0) bits |= HUP;
            s.onEvent(bits);
        }
    }
} else if (has_epoll) struct {
    const linux = std.os.linux;
    ep: i32 = -1,
    efd: i32 = -1,
    fn init(p: *@This()) !void {
        const ep = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        if (linux.errno(ep) != .SUCCESS) return error.SystemResources;
        p.ep = @intCast(ep);
        const efd = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
        if (linux.errno(efd) != .SUCCESS) return error.SystemResources;
        p.efd = @intCast(efd);
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .ptr = 0 } };
        if (linux.errno(linux.epoll_ctl(p.ep, linux.EPOLL.CTL_ADD, p.efd, &ev)) != .SUCCESS) return error.SystemResources;
    }
    fn deinit(p: *@This()) void {
        _ = linux.close(p.efd);
        _ = linux.close(p.ep);
    }
    fn poke(p: *@This()) void {
        const one: u64 = 1;
        _ = linux.write(p.efd, std.mem.asBytes(&one), 8);
    }
    fn add(p: *@This(), s: *IoSource) !void {
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN | linux.EPOLL.OUT | linux.EPOLL.RDHUP | linux.EPOLL.ET, .data = .{ .ptr = @intFromPtr(s) } };
        if (linux.errno(linux.epoll_ctl(p.ep, linux.EPOLL.CTL_ADD, s.fd, &ev)) != .SUCCESS) return error.SystemResources;
    }
    fn remove(p: *@This(), s: *IoSource) void {
        _ = linux.epoll_ctl(p.ep, linux.EPOLL.CTL_DEL, s.fd, null);
    }
    fn wait(p: *@This(), timeout_ns: ?u64) void {
        var evs: [64]linux.epoll_event = undefined;
        const ms: i32 = if (timeout_ns) |ns| @intCast(@min((ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms, std.math.maxInt(i32))) else -1;
        const rc = linux.epoll_wait(p.ep, &evs, evs.len, ms);
        if (linux.errno(rc) != .SUCCESS) return;
        for (evs[0..rc]) |e| {
            if (e.data.ptr == 0) {
                var buf: u64 = 0;
                _ = linux.read(p.efd, std.mem.asBytes(&buf), 8);
                continue;
            }
            const s: *IoSource = @ptrFromInt(e.data.ptr);
            var bits: u8 = 0;
            if (e.events & linux.EPOLL.IN != 0) bits |= READABLE;
            if (e.events & linux.EPOLL.OUT != 0) bits |= WRITABLE;
            if (e.events & (linux.EPOLL.HUP | linux.EPOLL.ERR | linux.EPOLL.RDHUP) != 0) bits |= HUP;
            s.onEvent(bits);
        }
    }
} else struct {
    // No reactor (Windows): sleep on a futex word, poked by futexWake.
    word: std.atomic.Value(u32) = .init(0),
    io: Io = undefined,
    fn init(p: *@This()) !void {
        _ = p;
    }
    fn deinit(p: *@This()) void {
        _ = p;
    }
    fn poke(p: *@This()) void {
        p.word.store(1, .release);
        p.io.futexWake(u32, &p.word.raw, 1);
    }
    fn add(p: *@This(), s: *IoSource) !void {
        _ = p;
        _ = s;
        return error.Unsupported;
    }
    fn remove(p: *@This(), s: *IoSource) void {
        _ = p;
        _ = s;
    }
    fn wait(p: *@This(), timeout_ns: ?u64) void {
        if (p.word.swap(0, .acquire) != 0) return;
        const t: Io.Timeout = if (timeout_ns) |ns| .{ .duration = .{ .raw = .fromNanoseconds(@intCast(ns)), .clock = .awake } } else .none;
        p.io.futexWaitTimeout(u32, &p.word.raw, 0, t) catch {};
        _ = p.word.swap(0, .acquire);
    }
};

// -------------------------------------------------------- blocking pool ---

/// Work run on the blocking pool (for calls the OS cannot do asynchronously,
/// such as regular file I/O). Embed one in a task.
pub fn Blocking(comptime Ctx: type, comptime Out: type, comptime func: fn (Ctx) Out) type {
    return struct {
        const Self = @This();
        op: Op = .{ .run = runOp },
        ctx: Ctx = undefined,
        out: Out = undefined,

        fn runOp(op: *Op) void {
            const self: *Self = @alignCast(@fieldParentPtr("op", op));
            self.out = func(self.ctx);
        }

        /// First poll submits `ctx`; ready with the result once a pool thread
        /// ran `func(ctx)`. A task must not finish while its op is in flight
        /// (`Runtime.deinit` waits for running ops).
        pub fn poll(self: *Self, cx: *rt.Context, ctx: Ctx) rt.Poll(Out) {
            switch (@atomicLoad(sync.WaitState, &self.op.state, .acquire)) {
                .done => {
                    self.op.state = .idle;
                    return .{ .ready = self.out };
                },
                .waiting => {
                    // Woken before the state was published: the pool thread
                    // holds the lock until it is.
                    const d = cx.runtime().driver();
                    d.pool_lock.lock();
                    const st = self.op.state;
                    d.pool_lock.unlock();
                    if (st != .done) return .pending;
                    self.op.state = .idle;
                    return .{ .ready = self.out };
                },
                else => {},
            }
            self.ctx = ctx;
            self.op.task = cx.header;
            self.op.state = .waiting;
            cx.runtime().driver().submit(&self.op) catch {
                self.op.state = .idle;
                self.out = func(ctx); // could not start a thread: run inline
                return .{ .ready = self.out };
            };
            return .pending;
        }
    };
}

pub const Op = struct {
    next: ?*Op = null,
    run: *const fn (*Op) void,
    task: ?*Header = null,
    state: sync.WaitState = .idle,
};

pub const ReadAtError = error{ IsDir, InputOutput, Unexpected };

/// Arguments of `FileRead`.
pub const ReadAt = struct { fd: fd_t, buf: []u8, offset: u64 };

fn preadBlocking(a: ReadAt) ReadAtError!usize {
    if (os == .windows) return error.Unexpected;
    while (true) {
        const rc = std.posix.system.pread(a.fd, a.buf.ptr, a.buf.len, @intCast(a.offset));
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .ISDIR => return error.IsDir,
            .IO => return error.InputOutput,
            else => return error.Unexpected,
        }
    }
}

/// Positional read of a regular file on the blocking pool. Regular files
/// are always "ready" for `kqueue`/`epoll`, so readiness I/O cannot help;
/// io_uring could, but is not used here.
pub const FileRead = Blocking(ReadAt, ReadAtError!usize, preadBlocking);

// ---------------------------------------------------------------- driver ---

pub const Driver = struct {
    r: *rt.Runtime,
    lock: sync.SpinLock = .{},
    heap: ?*Timer = null,
    timers: usize = 0,
    poller: Poller = .{},
    started: std.atomic.Value(bool) = .init(false),
    start_lock: sync.SpinLock = .{},
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    /// Odd while the driver may be dispatching events fetched from the OS.
    gen: std.atomic.Value(u64) = .init(0),
    /// True while the driver sleeps without a deadline (monitor idle).
    sleeping_forever: std.atomic.Value(bool) = .init(false),
    last_seq: []u32 = &.{},
    /// Times the monitor made a stuck worker's private tasks stealable.
    rescued: std.atomic.Value(usize) = .init(0),

    // blocking pool
    pool_lock: sync.SpinLock = .{},
    pool_head: ?*Op = null,
    pool_tail: ?*Op = null,
    pool_threads: [max_pool_threads]std.Thread = undefined,
    pool_started: usize = 0,
    pool_idle: usize = 0,
    pool_word: std.atomic.Value(u32) = .init(0),
    pool_inflight: std.atomic.Value(usize) = .init(0),

    pub const max_pool_threads = 16;

    pub fn init(d: *Driver, r: *rt.Runtime) void {
        d.* = .{ .r = r };
    }

    /// Starts the driver thread once (lazily).
    pub fn ensureStarted(d: *Driver) !void {
        if (d.started.load(.acquire)) return;
        d.start_lock.lock();
        defer d.start_lock.unlock();
        if (d.started.load(.acquire)) return;
        if (@hasField(Poller, "io")) d.poller.io = d.r.io;
        try d.poller.init();
        errdefer d.poller.deinit();
        d.last_seq = try d.r.gpa.alloc(u32, d.r.workers.len);
        @memset(d.last_seq, 0);
        d.thread = try std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{d});
        d.started.store(true, .release);
    }

    pub fn deinit(d: *Driver) void {
        // Blocking ops still running hold pointers into tasks: let them end.
        while (d.pool_inflight.load(.acquire) != 0) std.Thread.yield() catch {};
        d.stop.store(true, .seq_cst);
        d.pool_word.store(1, .release);
        d.r.io.futexWake(u32, &d.pool_word.raw, max_pool_threads);
        for (d.pool_threads[0..d.pool_started]) |t| t.join();
        if (!d.started.load(.acquire)) return;
        d.poller.poke();
        d.thread.?.join();
        d.poller.deinit();
        d.r.gpa.free(d.last_seq);
    }

    pub fn poke(d: *Driver) void {
        if (d.started.load(.acquire)) d.poller.poke();
    }

    /// Called by a worker that just started running after a park.
    pub fn workerBusy(d: *Driver) void {
        if (d.sleeping_forever.load(.monotonic)) {
            d.sleeping_forever.store(false, .monotonic);
            d.poke();
        }
    }

    fn insertLocked(d: *Driver, t: *Timer) bool {
        d.ensureStarted() catch @panic("rt: cannot start the driver thread");
        d.timers += 1;
        d.heap = if (d.heap) |h| meld(h, t) else t;
        return d.heap == t;
    }

    fn removeLocked(d: *Driver, t: *Timer) void {
        d.timers -= 1;
        if (d.heap == t) {
            d.heap = mergePairs(t.child);
        } else {
            const p = t.prev.?;
            if (p.child == t) p.child = t.sibling else p.sibling = t.sibling;
            if (t.sibling) |s| s.prev = p;
            if (mergePairs(t.child)) |sub| d.heap = meld(d.heap.?, sub);
        }
        t.child = null;
        t.sibling = null;
        t.prev = null;
    }

    /// Fires due timers; returns ns until the next deadline (null = none).
    fn fireTimers(d: *Driver) ?u64 {
        const now = nowNs(d.r.io);
        d.lock.lock();
        defer d.lock.unlock();
        while (d.heap) |t| {
            if (t.deadline > now) return t.deadline - now;
            d.removeLocked(t);
            const task = t.task.?;
            rt.wakeHeader(task);
            @atomicStore(sync.WaitState, &t.state, .done, .release);
        }
        return null;
    }

    fn add(d: *Driver, s: *IoSource) IoSource.Error!void {
        d.ensureStarted() catch return error.SystemResources;
        d.poller.add(s) catch return error.SystemResources;
    }

    fn remove(d: *Driver, s: *IoSource) void {
        d.poller.remove(s);
        // An event fetched before the removal may still be dispatched: wait
        // for the driver to finish the current batch.
        const g = d.gen.load(.acquire);
        if (g & 1 == 1) {
            d.poller.poke();
            while (d.gen.load(.acquire) == g) std.Thread.yield() catch {};
        }
    }

    fn run(d: *Driver) void {
        const monitor_ns = d.r.opts.monitor_interval_ns;
        while (!d.stop.load(.acquire)) {
            const next_timer = d.fireTimers();
            const busy = d.r.workers.len > 1 and d.r.anyWorkerAwake();
            var timeout = next_timer;
            if (busy and monitor_ns > 0) timeout = if (timeout) |t| @min(t, monitor_ns) else monitor_ns;
            d.sleeping_forever.store(timeout == null, .monotonic);
            _ = d.gen.fetchAdd(1, .acq_rel); // odd: may dispatch
            d.poller.wait(timeout);
            _ = d.gen.fetchAdd(1, .acq_rel); // even
            d.sleeping_forever.store(false, .monotonic);
            if (busy and monitor_ns > 0) d.monitor();
        }
    }

    /// Moves work a busy worker holds privately (its LIFO slot and its
    /// unpublished queue tail) to where others can take it, if the worker
    /// has been inside the same poll since the last check.
    fn monitor(d: *Driver) void {
        const r = d.r;
        if (r.workers.len < 2) return;
        for (r.workers, 0..) |*w, i| {
            const seq = w.poll_seq.load(.monotonic);
            const same = seq == d.last_seq[i];
            d.last_seq[i] = seq;
            if (!same or seq & 1 == 0) continue;
            var moved = false;
            if (w.lifo.load(.monotonic) != null) if (w.lifo.swap(null, .acquire)) |t| {
                t.next = null;
                r.injector.pushBatch(r.io, t, t, 1);
                moved = true;
            };
            if (w.queue.publishRemote()) moved = true;
            if (moved) {
                _ = d.rescued.fetchAdd(1, .monotonic);
                r.notifyParked();
            }
        }
    }

    // ---- blocking pool

    fn submit(d: *Driver, op: *Op) !void {
        _ = d.pool_inflight.fetchAdd(1, .acq_rel);
        d.pool_lock.lock();
        op.next = null;
        if (d.pool_tail) |t| t.next = op else d.pool_head = op;
        d.pool_tail = op;
        const need_thread = d.pool_idle == 0 and d.pool_started < max_pool_threads;
        var spawn_err: ?anyerror = null;
        if (need_thread) {
            if (std.Thread.spawn(.{ .stack_size = 1024 * 1024 }, poolMain, .{d})) |t| {
                d.pool_threads[d.pool_started] = t;
                d.pool_started += 1;
            } else |e| spawn_err = e;
        }
        if (spawn_err != null and d.pool_started == 0) {
            // No thread at all: take the op back.
            d.pool_head = null;
            d.pool_tail = null;
            d.pool_lock.unlock();
            _ = d.pool_inflight.fetchSub(1, .acq_rel);
            return error.SystemResources;
        }
        d.pool_lock.unlock();
        d.pool_word.store(1, .release);
        d.r.io.futexWake(u32, &d.pool_word.raw, 1);
    }

    fn poolMain(d: *Driver) void {
        while (true) {
            d.pool_lock.lock();
            const op = d.pool_head;
            if (op) |o| {
                d.pool_head = o.next;
                if (d.pool_head == null) d.pool_tail = null;
            } else d.pool_idle += 1;
            d.pool_lock.unlock();
            if (op) |o| {
                o.run(o);
                d.pool_lock.lock();
                rt.wakeHeader(o.task.?);
                @atomicStore(sync.WaitState, &o.state, .done, .release);
                d.pool_lock.unlock();
                _ = d.pool_inflight.fetchSub(1, .acq_rel);
                continue;
            }
            if (d.stop.load(.acquire)) return;
            while (d.pool_word.swap(0, .acquire) == 0) {
                if (d.stop.load(.acquire)) break;
                d.r.io.futexWaitUncancelable(u32, &d.pool_word.raw, 0);
            }
            d.pool_lock.lock();
            d.pool_idle -= 1;
            d.pool_lock.unlock();
            if (d.stop.load(.acquire) and d.pool_head == null) return;
        }
    }
};
