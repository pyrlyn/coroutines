//! `rt` — a work-stealing runtime for stackless tasks that can wait.
//!
//! A task is any struct `T` with
//!
//! ```zig
//! pub const Output = u64; // any type
//! pub fn poll(self: *T, cx: *rt.Context) rt.Poll(Output)
//! ```
//!
//! `poll` returns `.{ .ready = value }` when finished, or `.pending` after it
//! registered interest in something (a `JoinHandle`, a `Channel`, a
//! `Semaphore`, or a `Waker` it handed out). A pending task costs nothing
//! until it is woken: no thread waits for it, nothing polls it again.
//! An optional `pub fn deinit(self: *T) void` runs once, after the last poll
//! or when the task is aborted (unregister waiters there).
//!
//! Scheduler (the tokio / Go design, in Zig):
//! * a persistent pool of workers; an idle worker spins briefly, then parks
//!   on a futex; at most half of the workers search for work at a time;
//! * each worker owns a 256-slot FIFO run queue; idle workers steal half of a
//!   random victim's queue; a shared injector takes tasks from outside the
//!   runtime and overflow;
//! * a task woken by the task that is running goes into the worker's LIFO
//!   slot and runs next, on the same core, with no wake-up of another
//!   thread: channel ping-pong never leaves the worker;
//! * task frames (header + task + result) come from per-worker free lists
//!   backed by slabs: spawning allocates nothing in steady state.
//!
//! The runtime uses `std.Io` only to park threads (futex) and nothing else, so
//! it runs the same on `Io.Threaded` everywhere.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const queue_mod = @import("rt/queue.zig");
pub const sync = @import("rt/sync.zig");
pub const Channel = sync.Channel;
pub const Semaphore = sync.Semaphore;
pub const driver_mod = @import("rt/driver.zig");
pub const Timer = driver_mod.Timer;
pub const IoSource = driver_mod.IoSource;
pub const Blocking = driver_mod.Blocking;
pub const FileRead = driver_mod.FileRead;
pub const reactor_available = driver_mod.reactor_available;
const seq_mod = @import("rt/seq.zig");
pub const Flow = seq_mod.Flow;
pub const Seq = seq_mod.Seq;
pub const Race = seq_mod.Race;
pub const All = seq_mod.All;
pub const into = seq_mod.into;
pub const Sleep = seq_mod.Sleep;

/// Result of one `poll`.
pub fn Poll(comptime T: type) type {
    return union(enum) { pending, ready: T };
}

const cache_line = std.atomic.cache_line;

// Task state bits.
const SCHEDULED: u32 = 1; // in a run queue (or about to be)
const RUNNING: u32 = 2; // being polled
const NOTIFIED: u32 = 4; // woken while running: requeue after this poll
const COMPLETE: u32 = 8; // finished; never polled again
const CANCEL: u32 = 16; // abort requested
const ROOT: u32 = 32; // spawned by blockOn (fixed at spawn)

const join_none: usize = 0;
const join_done: usize = 1;

/// Type-erased task header at the start of every frame.
pub const Header = struct {
    state: std.atomic.Value(u32),
    refs: std.atomic.Value(u32),
    /// Run-queue / injector / free-list link.
    next: ?*Header = null,
    vtable: *const VTable,
    rt: *Runtime,
    /// 0 = nobody waits, 1 = complete, else the joiner's `*Header` (holding a ref).
    join_waker: std.atomic.Value(usize),
};

const VTable = struct {
    run: *const fn (*Header) void,
    class: u8,
    size: usize,
    /// Offset of the header in the frame (Zig may reorder struct fields).
    header_offset: usize,
};

/// Handed to `poll`. Identifies the running task.
pub const Context = struct {
    header: *Header,

    /// A waker for this task (takes a reference; call `wake` or `deinit`).
    pub fn waker(cx: *Context) Waker {
        _ = cx.header.refs.fetchAdd(1, .monotonic);
        return .{ .header = cx.header };
    }

    /// Asks to be polled again after other ready tasks. Return `.pending` after this.
    pub fn yieldNow(cx: *Context) void {
        wakeHeader(cx.header);
    }

    pub fn runtime(cx: *Context) *Runtime {
        return cx.header.rt;
    }
};

/// Wakes a pending task. Holds a reference to it, so it stays valid after the
/// task has finished.
pub const Waker = struct {
    header: *Header,

    /// Wakes and releases.
    pub fn wake(w: Waker) void {
        wakeHeader(w.header);
        unref(w.header);
    }
    pub fn wakeByRef(w: *const Waker) void {
        wakeHeader(w.header);
    }
    pub fn clone(w: *const Waker) Waker {
        _ = w.header.refs.fetchAdd(1, .monotonic);
        return w.*;
    }
    pub fn deinit(w: Waker) void {
        unref(w.header);
    }
};

/// Internal: wake without a reference. Callers guarantee `h` is alive (it is
/// registered in a structure it must leave before it can finish).
pub fn wakeHeader(h: *Header) void {
    var s = h.state.load(.acquire);
    std.debug.assert(s != FREE);
    while (true) {
        if (s & COMPLETE != 0) return;
        if (s & RUNNING != 0) {
            if (s & NOTIFIED != 0) return;
            s = h.state.cmpxchgWeak(s, s | NOTIFIED, .acq_rel, .acquire) orelse return;
            continue;
        }
        if (s & SCHEDULED != 0) return;
        s = h.state.cmpxchgWeak(s, s | SCHEDULED, .acq_rel, .acquire) orelse {
            h.rt.schedule(h, .wake);
            return;
        };
    }
}

fn unref(h: *Header) void {
    std.debug.assert(h.state.load(.monotonic) != FREE);
    if (h.refs.fetchSub(1, .acq_rel) == 1) h.rt.destroy(h);
}

fn complete(h: *Header) void {
    const prev = h.state.swap(COMPLETE, .acq_rel);
    const jw = h.join_waker.swap(join_done, .acq_rel);
    if (jw > join_done) {
        const j: *Header = @ptrFromInt(jw);
        wakeHeader(j);
        unref(j);
    }
    if (prev & ROOT != 0) {
        // The blockOn handle still holds a reference, so this does not free
        // the frame; once root_done is set the caller may free it.
        const r = h.rt;
        unref(h);
        r.root_done.store(1, .release);
        r.io.futexWake(u32, &r.root_done.raw, 1);
        return;
    }
    unref(h);
}

/// After a `.pending` poll: back to idle, or requeue if woken meanwhile.
fn afterPending(h: *Header) void {
    var s = h.state.load(.acquire);
    while (true) {
        if (s & NOTIFIED != 0) {
            const ns = (s & ~(RUNNING | NOTIFIED)) | SCHEDULED;
            s = h.state.cmpxchgWeak(s, ns, .acq_rel, .acquire) orelse {
                h.rt.schedule(h, .requeue);
                return;
            };
        } else {
            s = h.state.cmpxchgWeak(s, s & ~RUNNING, .acq_rel, .acquire) orelse return;
        }
    }
}

/// Outcome of a task: its output, or `error.Canceled` after `abort`.
pub fn Result(comptime T: type) type {
    return error{Canceled}!T.Output;
}

fn Frame(comptime T: type) type {
    if (!@hasDecl(T, "poll") or !@hasDecl(T, "Output"))
        @compileError(@typeName(T) ++ " must declare `pub const Output` and `pub fn poll(*T, *rt.Context) rt.Poll(Output)`");
    return struct {
        const Self = @This();
        header: Header,
        /// The task until it completes, then its result (the task is gone).
        body: extern union { task: Raw(T), result: Raw(Result(T)) },

        const size = @sizeOf(Self);
        const class: u8 = classFor(size);
        const vtable: VTable = .{ .run = run, .class = class, .size = size, .header_offset = @offsetOf(Self, "header") };

        fn task(f: *Self) *T {
            return @ptrCast(&f.body.task);
        }
        fn result(f: *Self) *Result(T) {
            return @ptrCast(&f.body.result);
        }
        fn finish(f: *Self, r: Result(T)) void {
            if (@hasDecl(T, "deinit")) f.task().deinit();
            f.result().* = r;
            complete(&f.header);
        }

        fn run(h: *Header) void {
            const f: *Self = @alignCast(@fieldParentPtr("header", h));
            // SCHEDULED -> RUNNING in one RMW (bit 0 set, bit 1 clear).
            const s = h.state.fetchAdd(RUNNING - SCHEDULED, .acquire);
            std.debug.assert(s & SCHEDULED != 0 and s & (RUNNING | COMPLETE) == 0);
            if (s & CANCEL != 0) return f.finish(error.Canceled);
            var cx: Context = .{ .header = h };
            switch (f.task().poll(&cx)) {
                .ready => |v| f.finish(v),
                .pending => afterPending(h),
            }
        }
    };
}

/// Storage for a `T` usable in an extern union.
fn Raw(comptime T: type) type {
    return extern struct { bytes: [@sizeOf(T)]u8 align(@alignOf(T)) };
}

/// Owner's handle to a spawned task: await its result, or abort it.
/// Drop it with `deinit` (detach) if the result is not needed.
pub fn JoinHandle(comptime T: type) type {
    return struct {
        const Self = @This();
        header: ?*Header,

        /// Poll for the result from inside a task. On `.ready` the handle is
        /// consumed.
        pub fn poll(self: *Self, cx: *Context) Poll(Result(T)) {
            const h = self.header.?;
            var jw = h.join_waker.load(.acquire);
            if (jw == join_none) {
                _ = cx.header.refs.fetchAdd(1, .monotonic);
                if (h.join_waker.cmpxchgStrong(join_none, @intFromPtr(cx.header), .acq_rel, .acquire)) |actual| {
                    _ = cx.header.refs.fetchSub(1, .monotonic); // we are running: not the last ref
                    jw = actual;
                } else return .pending;
            }
            if (jw == join_done) return .{ .ready = self.take() };
            std.debug.assert(jw == @intFromPtr(cx.header)); // one joiner per handle
            return .pending;
        }

        /// `poll` that gives up at `deadline` (see `Runtime.now`) with
        /// `error.Timeout`; the handle stays valid and the task keeps running.
        pub fn pollDeadline(self: *Self, cx: *Context, t: *Timer, deadline: u64) Poll(error{Timeout}!Result(T)) {
            switch (self.poll(cx)) {
                .ready => |r| {
                    _ = t.cancel();
                    return .{ .ready = r };
                },
                .pending => {},
            }
            if (t.sleepUntil(cx, deadline) == .pending) return .pending;
            const h = self.header.?;
            if (h.join_waker.cmpxchgStrong(@intFromPtr(cx.header), join_none, .acq_rel, .acquire)) |actual| {
                std.debug.assert(actual == join_done);
                return .{ .ready = self.take() };
            }
            _ = cx.header.refs.fetchSub(1, .monotonic); // running: not the last ref
            return .{ .ready = error.Timeout };
        }

        /// Non-blocking check; null while running.
        pub fn tryResult(self: *Self) ?Result(T) {
            const h = self.header.?;
            if (h.join_waker.load(.acquire) != join_done) return null;
            return self.take();
        }

        pub fn isFinished(self: *const Self) bool {
            return self.header.?.join_waker.load(.acquire) == join_done;
        }

        fn take(self: *Self) Result(T) {
            const h = self.header.?;
            const f: *Frame(T) = @alignCast(@fieldParentPtr("header", h));
            const r = f.result().*;
            self.header = null;
            unref(h);
            return r;
        }

        /// Requests cancellation: the task is not polled again; its `deinit`
        /// runs and the result becomes `error.Canceled`. No effect once it
        /// has finished.
        pub fn abort(self: *Self) void {
            const h = self.header.?;
            _ = h.state.fetchOr(CANCEL, .acq_rel);
            wakeHeader(h);
        }

        /// Detach: the task keeps running; its frame is freed when it ends.
        pub fn deinit(self: *Self) void {
            if (self.header) |h| {
                // A registered joiner reference is released by `complete`.
                self.header = null;
                unref(h);
            }
        }
    };
}

// ---------------------------------------------------------------- frames ---

const classes = [_]usize{ 64, 128, 256, 512, 1024, 2048, 4096 };
const n_classes = classes.len;
const big_class: u8 = 0xff;
const slab_bytes = 64 * 1024;
const local_free_max = 256;

fn classFor(comptime size: usize) u8 {
    for (classes, 0..) |c, i| if (size <= c) return @intCast(i);
    return big_class;
}

/// State value of a frame on a free list (debug check).
const FREE: u32 = 0xF7EE0000;

const FreeList = struct {
    head: ?*Header = null,
    count: usize = 0,
    fn push(l: *FreeList, h: *Header) void {
        if (std.debug.runtime_safety) h.state.raw = FREE;
        h.next = l.head;
        l.head = h;
        l.count += 1;
    }
    fn pop(l: *FreeList) ?*Header {
        const h = l.head orelse return null;
        if (std.debug.runtime_safety and h.state.raw != FREE) std.debug.panic("frame {*} on a free list was overwritten", .{h});
        l.head = h.next;
        l.count -= 1;
        return h;
    }
};

const Slab = struct { next: ?*Slab, bytes: []align(cache_line) u8 };

// ------------------------------------------------------------- injector ---

const Injector = struct {
    lock: sync.SpinLock = .{},
    head: ?*Header = null,
    tail: ?*Header = null,
    len: std.atomic.Value(usize) = .init(0),

    pub fn pushBatch(inj: *Injector, io: Io, first: *Header, last: *Header, count: usize) void {
        _ = io;
        last.next = null;
        inj.lock.lock();
        if (inj.tail) |t| t.next = first else inj.head = first;
        inj.tail = last;
        _ = inj.len.fetchAdd(count, .seq_cst);
        inj.lock.unlock();
    }

    /// Pops up to `max` tasks; returns the first, the rest are linked via `next`.
    fn popBatch(inj: *Injector, io: Io, max: usize, got: *usize) ?*Header {
        _ = io;
        if (inj.len.load(.seq_cst) == 0) return null;
        // Another worker is taking a batch or a producer is pushing: do not
        // queue up behind it, there is other work to look for.
        if (!inj.lock.tryLock()) return null;
        defer inj.lock.unlock();
        const first = inj.head orelse return null;
        var last = first;
        var n: usize = 1;
        while (n < max) : (n += 1) last = last.next orelse break;
        inj.head = last.next;
        if (inj.head == null) inj.tail = null;
        last.next = null;
        _ = inj.len.fetchSub(n, .seq_cst);
        got.* = n;
        return first;
    }
};

// ----------------------------------------------------------------- idle ---

const Idle = struct {
    mutex: Io.Mutex = .init,
    searching: std.atomic.Value(u32) align(cache_line) = .init(0),
    num_idle: std.atomic.Value(u32) = .init(0),
    /// Stack of parked worker indices (guarded by `mutex`).
    stack: []u32 = &.{},
    is_idle: []bool = &.{},
};

// --------------------------------------------------------------- worker ---

const LocalQueue = queue_mod.LocalQueue(Header);

const Worker = struct {
    queue: LocalQueue = .{},
    rt: *Runtime align(cache_line),
    index: u32,
    /// Runs next. Atomic only so the monitor can take it from a stuck worker.
    lifo: std.atomic.Value(?*Header) = .init(null),
    lifo_streak: u8 = 0,
    searching: bool = false,
    polling: bool = false,
    /// Odd while a task is being polled (read by the monitor).
    poll_seq: std.atomic.Value(u32) = .init(0),
    tick: u32 = 0,
    rng: u64,
    free: [n_classes]FreeList = @splat(.{}),
    park_word: std.atomic.Value(u32) align(cache_line) = .init(0),

    fn nextRandom(w: *Worker, n: u32) u32 {
        w.rng ^= w.rng << 13;
        w.rng ^= w.rng >> 7;
        w.rng ^= w.rng << 17;
        return @intCast(w.rng % n);
    }
};

threadlocal var tl_worker: ?*Worker = null;

/// Options for `Runtime.init`.
pub const Options = struct {
    /// Worker threads; 0 = CPU count. Ignored with `current_thread`.
    workers: usize = 0,
    /// No threads at all: `blockOn` runs the scheduler on the calling thread
    /// (tokio's `current_thread`).
    current_thread: bool = false,
    /// Stack size of each worker thread.
    stack_size: usize = 1024 * 1024,
    /// Spin rounds an idle worker makes before parking.
    spin_rounds: u32 = 64,
    /// How often the driver checks for a worker stuck in one long poll while
    /// holding tasks nobody else can see (0 = never). Multi-thread only.
    monitor_interval_ns: u64 = std.time.ns_per_ms,
};

pub const max_lifo_streak = 3;
/// Tasks a poll may push before they are made stealable.
const publish_batch = 8;
const injector_check_interval = 61;

pub const Runtime = struct {
    gpa: Allocator,
    io: Io,
    opts: Options,
    workers: []Worker,
    threads: []std.Thread,
    injector: Injector = .{},
    idle: Idle = .{},
    shutdown_flag: std.atomic.Value(bool) = .init(false),
    root_done: std.atomic.Value(u32) = .init(0),
    pool_mutex: Io.Mutex = .init,
    pool: [n_classes]FreeList = @splat(.{}),
    slabs: ?*Slab = null,
    /// Live task frames (debug builds only; for leak checks).
    live: std.atomic.Value(usize) = .init(0),
    drv: driver_mod.Driver = undefined,

    const track_live = std.debug.runtime_safety;

    /// Starts the workers. `r` must not move afterwards. `gpa` must be
    /// thread-safe.
    pub fn init(r: *Runtime, gpa: Allocator, io: Io, opts: Options) !void {
        const n: usize = if (opts.current_thread) 1 else if (opts.workers == 0) (std.Thread.getCpuCount() catch 1) else opts.workers;
        r.* = .{ .gpa = gpa, .io = io, .opts = opts, .workers = &.{}, .threads = &.{} };
        r.drv.init(r);
        r.workers = try gpa.alignedAlloc(Worker, .fromByteUnits(cache_line), n);
        errdefer gpa.free(r.workers);
        for (r.workers, 0..) |*w, i| w.* = .{ .rt = r, .index = @intCast(i), .rng = (0x9E3779B97F4A7C15 ^ (i *% 0xBF58476D1CE4E5B9)) | 1 };
        r.idle.stack = try gpa.alloc(u32, n);
        errdefer gpa.free(r.idle.stack);
        r.idle.is_idle = try gpa.alloc(bool, n);
        errdefer gpa.free(r.idle.is_idle);
        @memset(r.idle.is_idle, false);
        if (opts.current_thread) return;
        if (n > 1 and opts.monitor_interval_ns > 0) try r.drv.ensureStarted();
        errdefer r.drv.deinit();
        r.threads = try gpa.alloc(std.Thread, n);
        var started: usize = 0;
        errdefer {
            r.shutdown();
            for (r.threads[0..started]) |t| t.join();
            gpa.free(r.threads);
        }
        while (started < n) : (started += 1) {
            r.threads[started] = try std.Thread.spawn(.{ .stack_size = opts.stack_size }, workerMain, .{&r.workers[started]});
        }
    }

    /// Stops and joins the workers and frees all memory. Tasks still
    /// pending are dropped without running `deinit`.
    pub fn deinit(r: *Runtime) void {
        r.drv.deinit();
        r.shutdown();
        for (r.threads) |t| t.join();
        if (r.threads.len > 0) r.gpa.free(r.threads);
        var s = r.slabs;
        while (s) |slab| {
            s = slab.next;
            r.gpa.free(slab.bytes);
        }
        r.gpa.free(r.idle.stack);
        r.gpa.free(r.idle.is_idle);
        r.gpa.free(r.workers);
    }

    fn shutdown(r: *Runtime) void {
        r.shutdown_flag.store(true, .seq_cst);
        for (r.workers) |*w| {
            w.park_word.store(1, .release);
            r.io.futexWake(u32, &w.park_word.raw, 1);
        }
    }

    /// The driver (timers, reactor, blocking pool, monitor).
    pub fn driver(r: *Runtime) *driver_mod.Driver {
        return &r.drv;
    }

    /// Nanoseconds on the monotonic clock used by timers.
    pub fn now(r: *Runtime) u64 {
        return driver_mod.nowNs(r.io);
    }

    /// Whether some worker is not parked.
    pub fn anyWorkerAwake(r: *Runtime) bool {
        return r.idle.num_idle.load(.monotonic) < r.workers.len;
    }

    /// Times the monitor made a stuck worker's private tasks stealable.
    pub fn monitorRescues(r: *Runtime) usize {
        return r.drv.rescued.load(.monotonic);
    }

    /// Number of task frames alive (debug builds; 0 in release).
    pub fn liveTasks(r: *const Runtime) usize {
        return r.live.load(.acquire);
    }

    /// Spawns `task` and returns its handle. From a task of this runtime it
    /// goes to the current worker's queue; from elsewhere, to the injector.
    pub fn spawn(r: *Runtime, comptime T: type, task: T) Allocator.Error!JoinHandle(T) {
        const h = try r.spawnInner(T, task, true, false);
        return .{ .header = h };
    }

    /// Spawns without a handle.
    pub fn spawnDetached(r: *Runtime, comptime T: type, task: T) Allocator.Error!void {
        _ = try r.spawnInner(T, task, false, false);
    }

    fn spawnInner(r: *Runtime, comptime T: type, task: T, handle: bool, root: bool) Allocator.Error!*Header {
        const F = Frame(T);
        comptime std.debug.assert(@alignOf(F) <= cache_line);
        const mem = try r.allocFrame(F.class, F.size);
        const f: *F = @ptrCast(@alignCast(mem));
        f.header = .{
            .state = .init(if (root) SCHEDULED | ROOT else SCHEDULED),
            .refs = .init(if (handle) 2 else 1),
            .vtable = &F.vtable,
            .rt = r,
            .join_waker = .init(join_none),
        };
        f.task().* = task;
        if (track_live) _ = r.live.fetchAdd(1, .monotonic);
        r.schedule(&f.header, .spawn);
        return &f.header;
    }

    /// Runs `task` to completion and returns its result. With
    /// `current_thread` the calling thread runs the scheduler meanwhile;
    /// otherwise it parks until a worker finishes the task. One `blockOn`
    /// at a time per runtime.
    pub fn blockOn(r: *Runtime, comptime T: type, task: T) (Allocator.Error || error{Canceled})!T.Output {
        r.root_done.store(0, .release);
        var h: JoinHandle(T) = .{ .header = try r.spawnInner(T, task, true, true) };
        if (r.opts.current_thread) {
            const prev = tl_worker;
            defer tl_worker = prev;
            r.workerLoop(&r.workers[0], &r.root_done);
        } else {
            while (r.root_done.load(.acquire) == 0) r.io.futexWaitUncancelable(u32, &r.root_done.raw, 0);
        }
        return h.tryResult().?;
    }

    const ScheduleKind = enum { spawn, wake, requeue };

    fn schedule(r: *Runtime, h: *Header, kind: ScheduleKind) void {
        if (tl_worker) |w| if (w.rt == r) {
            if (kind == .wake and w.polling) {
                // Run next on this core. A displaced task becomes stealable.
                if (w.lifo.load(.monotonic) == null) {
                    // Only this worker fills the slot: a plain store is enough.
                    w.lifo.store(h, .release);
                } else if (w.lifo.swap(h, .acq_rel)) |prev| {
                    w.queue.push(prev, r, overflowToInjector);
                    w.queue.publish();
                    r.notifyParked();
                }
                return;
            }
            w.queue.push(h, r, overflowToInjector);
            // Publish in batches; `runTask` publishes the rest after the poll.
            // A lone task is most likely run by this worker as soon as the
            // current one waits for it (spawn + join): waking another thread
            // for it would cost a futex syscall per spawn.
            if (w.queue.unpublished() >= publish_batch) {
                w.queue.publish();
                r.notifyParked();
            }
            return;
        };
        h.next = null;
        r.injector.pushBatch(r.io, h, h, 1);
        r.notifyParked();
    }

    fn overflowToInjector(r: *Runtime, first: *Header, last: *Header, count: usize) void {
        r.injector.pushBatch(r.io, first, last, count);
    }

    // ---- frames

    fn allocFrame(r: *Runtime, class: u8, size: usize) Allocator.Error!*anyopaque {
        if (class == big_class) {
            const m = try r.gpa.alignedAlloc(u8, .fromByteUnits(cache_line), size);
            return m.ptr;
        }
        if (tl_worker) |w| if (w.rt == r) {
            if (w.free[class].pop()) |h| return h;
            return r.refill(&w.free[class], class);
        };
        r.pool_mutex.lockUncancelable(r.io);
        defer r.pool_mutex.unlock(r.io);
        if (r.pool[class].pop()) |h| return h;
        return r.newSlabLocked(null, class);
    }

    fn refill(r: *Runtime, local: *FreeList, class: u8) Allocator.Error!*anyopaque {
        r.pool_mutex.lockUncancelable(r.io);
        defer r.pool_mutex.unlock(r.io);
        const g = &r.pool[class];
        var moved: usize = 0;
        while (moved < 64) : (moved += 1) local.push(g.pop() orelse break);
        if (local.pop()) |h| return h;
        return r.newSlabLocked(local, class);
    }

    fn newSlabLocked(r: *Runtime, local: ?*FreeList, class: u8) Allocator.Error!*anyopaque {
        const fsize = classes[class];
        const frames = @max(16, slab_bytes / fsize);
        const bytes = try r.gpa.alignedAlloc(u8, .fromByteUnits(cache_line), fsize * frames + @sizeOf(Slab));
        const slab: *Slab = @ptrCast(@alignCast(bytes.ptr + fsize * frames));
        slab.* = .{ .next = r.slabs, .bytes = bytes };
        r.slabs = slab;
        const list = local orelse &r.pool[class];
        // Push in reverse so frames are handed out in address order.
        var i: usize = frames - 1;
        while (i >= 1) : (i -= 1) list.push(@ptrCast(@alignCast(bytes.ptr + i * fsize)));
        return bytes.ptr;
    }

    fn destroy(r: *Runtime, h: *Header) void {
        std.debug.assert(h.state.load(.monotonic) & COMPLETE != 0);
        if (track_live) _ = r.live.fetchSub(1, .monotonic);
        const vt = h.vtable;
        // Free lists hold frame base addresses, viewed as a `Header`.
        const base: *Header = @ptrFromInt(@intFromPtr(h) - vt.header_offset);
        if (vt.class == big_class) {
            const p: [*]align(cache_line) u8 = @ptrCast(@alignCast(base));
            r.gpa.free(p[0..vt.size]);
            return;
        }
        if (tl_worker) |w| if (w.rt == r) {
            const l = &w.free[vt.class];
            l.push(base);
            if (l.count > local_free_max) {
                r.pool_mutex.lockUncancelable(r.io);
                defer r.pool_mutex.unlock(r.io);
                while (l.count > local_free_max / 2) r.pool[vt.class].push(l.pop().?);
            }
            return;
        };
        r.pool_mutex.lockUncancelable(r.io);
        defer r.pool_mutex.unlock(r.io);
        r.pool[vt.class].push(base);
    }

    // ---- workers

    fn workerMain(w: *Worker) void {
        w.rt.workerLoop(w, null);
    }

    fn workerLoop(r: *Runtime, w: *Worker, until: ?*std.atomic.Value(u32)) void {
        tl_worker = w;
        while (true) {
            if (r.shutdown_flag.load(.acquire)) return;
            if (until) |u| if (u.load(.acquire) != 0) return;
            if (r.nextLocal(w) orelse r.findWork(w)) |t| {
                r.runTask(w, t);
                continue;
            }
            var found: ?*Header = null;
            var i: u32 = 0;
            while (i < r.opts.spin_rounds) : (i += 1) {
                for (0..8) |_| std.atomic.spinLoopHint();
                found = r.findWork(w);
                if (found != null or r.shutdown_flag.load(.acquire)) break;
            }
            if (found) |t| {
                r.runTask(w, t);
                continue;
            }
            if (until) |u| if (u.load(.acquire) != 0) return;
            r.park(w);
        }
    }

    fn runTask(r: *Runtime, w: *Worker, t: *Header) void {
        if (w.searching) {
            w.searching = false;
            // The last searcher found work: get another one going.
            if (r.idle.searching.fetchSub(1, .seq_cst) == 1) r.notifyParked();
        }
        w.polling = true;
        const seq = w.poll_seq.raw;
        w.poll_seq.store(seq +% 1, .monotonic);
        t.vtable.run(t);
        w.poll_seq.store(seq +% 2, .monotonic);
        w.polling = false;
        if (w.queue.unpublished() != 0) {
            w.queue.publish();
            if (w.queue.ownerLen() > 1) r.notifyParked();
        }
    }

    fn nextLocal(r: *Runtime, w: *Worker) ?*Header {
        w.tick +%= 1;
        if (w.tick % injector_check_interval == 0) {
            if (r.takeInjector(w)) |t| return t;
        }
        if (w.lifo.load(.monotonic) != null) if (w.lifo.swap(null, .acquire)) |t| {
            if (w.lifo_streak < max_lifo_streak) {
                w.lifo_streak += 1;
                return t;
            }
            w.queue.push(t, r, overflowToInjector);
        };
        w.lifo_streak = 0;
        if (w.queue.pop()) |t| {
            if (w.queue.ownerLen() != 0) {
                w.queue.publish();
                r.notifyParked();
            }
            return t;
        }
        return r.takeInjector(w);
    }

    fn takeInjector(r: *Runtime, w: *Worker) ?*Header {
        const n: usize = r.workers.len;
        const want = @min(queue_mod.capacity / 2, r.injector.len.load(.monotonic) / n + 1);
        var got: usize = 0;
        const first = r.injector.popBatch(r.io, want, &got) orelse return null;
        var it = first.next;
        while (it) |t| {
            it = t.next;
            w.queue.push(t, r, overflowToInjector);
        }
        w.queue.publish();
        if (got > 1) r.notifyParked();
        return first;
    }

    fn findWork(r: *Runtime, w: *Worker) ?*Header {
        const n: u32 = @intCast(r.workers.len);
        if (n > 1) {
            if (!w.searching) {
                // At most half of the workers search at once.
                const s = r.idle.searching.load(.seq_cst);
                if (2 * s >= n) return r.takeInjector(w);
                _ = r.idle.searching.fetchAdd(1, .seq_cst);
                w.searching = true;
            }
            const start = w.nextRandom(n);
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const v = (start + i) % n;
                if (v == w.index) continue;
                if (r.workers[v].queue.stealInto(&w.queue)) |t| return t;
            }
        }
        return r.takeInjector(w);
    }

    fn anyWork(r: *Runtime) bool {
        if (r.injector.len.load(.seq_cst) != 0) return true;
        for (r.workers) |*v| if (!v.queue.isEmpty()) return true;
        return false;
    }

    fn park(r: *Runtime, w: *Worker) void {
        if (w.searching) {
            w.searching = false;
            if (r.idle.searching.fetchSub(1, .seq_cst) == 1 and r.anyWork()) return;
        }
        r.idle.mutex.lockUncancelable(r.io);
        r.idle.stack[r.idle.num_idle.load(.monotonic)] = w.index;
        r.idle.is_idle[w.index] = true;
        _ = r.idle.num_idle.fetchAdd(1, .seq_cst);
        r.idle.mutex.unlock(r.io);

        if (r.anyWork() or r.shutdown_flag.load(.seq_cst)) {
            if (r.unidle(w)) return;
            // A notifier already took us: its token is on the way.
        }
        while (w.park_word.swap(0, .acquire) == 0) {
            r.io.futexWaitUncancelable(u32, &w.park_word.raw, 0);
        }
        // The notifier counted us as searching.
        if (!r.shutdown_flag.load(.acquire)) w.searching = true;
        r.drv.workerBusy();
    }

    /// Removes `w` from the idle set if it is still there.
    fn unidle(r: *Runtime, w: *Worker) bool {
        r.idle.mutex.lockUncancelable(r.io);
        defer r.idle.mutex.unlock(r.io);
        if (!r.idle.is_idle[w.index]) return false;
        const n = r.idle.num_idle.load(.monotonic);
        for (r.idle.stack[0..n], 0..) |v, i| if (v == w.index) {
            r.idle.stack[i] = r.idle.stack[n - 1];
            break;
        };
        r.idle.is_idle[w.index] = false;
        _ = r.idle.num_idle.fetchSub(1, .seq_cst);
        return true;
    }

    /// Wakes one parked worker as a searcher, unless one already searches.
    pub fn notifyParked(r: *Runtime) void {
        if (r.idle.searching.load(.seq_cst) != 0) return;
        if (r.idle.num_idle.load(.seq_cst) == 0) return;
        r.idle.mutex.lockUncancelable(r.io);
        const n = r.idle.num_idle.load(.monotonic);
        if (n == 0 or r.idle.searching.load(.seq_cst) != 0) {
            r.idle.mutex.unlock(r.io);
            return;
        }
        const idx = r.idle.stack[n - 1];
        r.idle.is_idle[idx] = false;
        _ = r.idle.num_idle.fetchSub(1, .seq_cst);
        _ = r.idle.searching.fetchAdd(1, .seq_cst);
        r.idle.mutex.unlock(r.io);
        const v = &r.workers[idx];
        v.park_word.store(1, .release);
        r.io.futexWake(u32, &v.park_word.raw, 1);
    }
};

test {
    _ = queue_mod;
    _ = sync;
    _ = driver_mod;
    _ = seq_mod;
    _ = @import("rt/tests.zig");
}
