//! Stackless coroutines as explicit state machines.
//!
//! A coroutine is any struct `T` with `pub fn step(self: *T) Step`. It keeps
//! its own progress in a state field and returns `.yield` to give control
//! back to the scheduler or `.done` when finished. Switching is a plain
//! function return + call: no allocation, no stack switching. Tasks live in
//! caller-provided storage (a slice of `T`).
const std = @import("std");

/// What a coroutine's `step` returns.
/// * `.yield` — not finished; the scheduler will call `step` again later.
/// * `.done`  — finished; `step` is never called on this task again.
pub const Step = enum { yield, done };

/// Returned by `runAll` / `runParallel` when the cancel flag was observed.
pub const Error = error{Canceled};

fn checkTask(comptime T: type) void {
    if (!@hasDecl(T, "step")) @compileError(@typeName(T) ++ " must declare `pub fn step(self: *" ++ @typeName(T) ++ ") Step`");
}

/// Runs every task round-robin until all are done, on the calling thread.
///
/// Params:
/// * `T` — coroutine type with `pub fn step(self: *T) Step`.
/// * `tasks` — caller-owned storage; nothing is allocated.
/// * `cancel` — optional flag; `null` = run to completion.
///
/// Returns the total number of `step` calls, or `error.Canceled`.
///
/// Note: the slice is **permuted in place** (finished tasks are swapped to the
/// end), so identify tasks by a field, not by their index.
///
/// ```zig
/// const Countdown = struct {
///     left: u32,
///     pub fn step(c: *Countdown) Step {
///         c.left -= 1;
///         return if (c.left == 0) .done else .yield;
///     }
/// };
/// var tasks: [3]Countdown = .{ .{ .left = 1 }, .{ .left = 2 }, .{ .left = 3 } };
/// const steps = try runAll(Countdown, &tasks, null); // steps == 6
/// ```
/// Finished tasks are moved to the end of `tasks` (the slice is permuted in
/// place, so tasks must not rely on their index). Returns the number of
/// `step` calls made. If `cancel` is set and becomes true, stops after the
/// current round and returns `error.Canceled`; unfinished tasks are then at
/// the front of `tasks`.
pub fn runAll(comptime T: type, tasks: []T, cancel: ?*const std.atomic.Value(bool)) Error!u64 {
    checkTask(T);
    var live = tasks.len;
    var steps: u64 = 0;
    while (live > 0) {
        if (cancel) |c| if (c.load(.acquire)) return error.Canceled;
        var i: usize = 0;
        while (i < live) {
            steps += 1;
            if (tasks[i].step() == .done) {
                live -= 1;
                std.mem.swap(T, &tasks[i], &tasks[live]);
            } else i += 1;
        }
    }
    return steps;
}

/// Options for `runParallel`. All fields have defaults: `.{}` is valid.
pub const ParallelOptions = struct {
    /// Total worker count including the calling thread. 0 = CPU count.
    threads: usize = 0,
    /// Tasks claimed from the shared queue at a time.
    chunk: usize = 64,
    /// Cooperative cancellation flag, checked between rounds.
    cancel: ?*const std.atomic.Value(bool) = null,
    /// Stack size for spawned workers. The calling thread keeps its own stack.
    stack_size: usize = worker_stack_size,
    /// Whether the calling thread works too. With `false` it only waits and
    /// all `threads` workers are spawned, so steps that need `stack_size` get
    /// it even when the caller's stack is smaller. Should no thread spawn at
    /// all, the caller works anyway: the tasks still have to run.
    caller_works: bool = true,
};

/// Default stack size for worker threads (steps run on it). 256 KiB fails
/// with glibc on aarch64 Linux, so stay at 1 MiB.
pub const worker_stack_size = 1024 * 1024;

/// Hard cap on worker threads; their handles live on the caller's stack.
pub const max_threads = 64;

threadlocal var current_worker: ?usize = null;

/// This thread's index in the innermost `runParallel` it is working in, in
/// `0..opts.threads`, or `null` outside one. A step has no other way to reach
/// per-worker state, such as an arena. A calling thread that works is index 0.
pub fn currentWorker() ?usize {
    return current_worker;
}

/// A half-open range of indices claimed from a `Cursor`.
pub const Range = struct { start: usize, end: usize };

/// Hands out `[0, total)` in chunks, each index exactly once, to any number of
/// threads. Lock-free: one `fetchAdd` per claim. This is `runParallel`'s work
/// queue, for loops over indices that are not coroutines. A claim synchronises
/// nothing, so what the items need must be visible before the threads start.
/// The fields are internal: make one with `init`.
///
/// ```zig
/// var cursor: Cursor = .init(items.len, 64);
/// // on every thread:
/// while (cursor.claim()) |r| for (items[r.start..r.end]) |*item| process(item);
/// ```
pub const Cursor = struct {
    next: std.atomic.Value(usize) = .init(0),
    total: usize,
    chunk: usize,

    /// `chunk` is clamped to `1..total`: a claim has to move the cursor, and a
    /// chunk near the top of `usize` would wrap it back to indices already
    /// handed out.
    pub fn init(total: usize, chunk: usize) Cursor {
        return .{ .total = total, .chunk = std.math.clamp(chunk, 1, @max(1, total)) };
    }

    /// The next chunk, or `null` when every index has been handed out.
    pub fn claim(c: *Cursor) ?Range {
        const start = c.next.fetchAdd(c.chunk, .monotonic);
        if (start >= c.total) return null;
        return .{ .start = start, .end = @min(start + c.chunk, c.total) };
    }

    /// Like `claim`, but the chunk shrinks towards 1 as the queue drains:
    /// `clamp(remaining / (2 * workers), 1, chunk)`. Early claims stay large
    /// (few atomics); the last ones are small, so no worker is left holding a
    /// big chunk while the others are idle. One `cmpxchg` loop per claim.
    pub fn claimTapered(c: *Cursor, workers: usize) ?Range {
        var start = c.next.load(.monotonic);
        while (start < c.total) {
            const size = std.math.clamp((c.total - start) / (2 * @max(1, workers)), 1, c.chunk);
            start = c.next.cmpxchgWeak(start, start + size, .monotonic, .monotonic) orelse
                return .{ .start = start, .end = start + size };
        }
        return null;
    }
};

/// Runs tasks on up to `opts.threads` OS threads (including the caller's),
/// never more than there are chunks of `opts.chunk` tasks.
///
/// Params: `T` and `tasks` as in `runAll`; `opts` see `ParallelOptions`.
/// Returns when every task is done (or `error.Canceled`); all threads have
/// been joined by then. Each task is stepped by exactly one thread, so a
/// task's own fields need no synchronisation; shared state does.
///
/// ```zig
/// try runParallel(Countdown, tasks, .{ .threads = 4, .chunk = 64 });
/// ```
/// Work distribution is a
/// lock-free queue: one `Cursor` over `tasks`; each worker claims a chunk
/// (`Cursor.claimTapered`: at most `opts.chunk`, smaller near the end)
/// and runs it round-robin to completion, then claims the next. Unlike
/// `runAll`, tasks larger than two words in chunks of up to 1024 are not
/// moved, so the slice keeps its order. The
/// calling thread works too unless `opts.caller_works` is
/// false. All spawned threads are joined before returning (deterministic
/// shutdown), also on cancellation. If a thread cannot be spawned, the run
/// continues with fewer workers.
pub fn runParallel(comptime T: type, tasks: []T, opts: ParallelOptions) Error!void {
    checkTask(T);
    const want = if (opts.threads == 0) (std.Thread.getCpuCount() catch 1) else opts.threads;
    var shared: Shared(T) = .{ .tasks = tasks, .cursor = .init(tasks.len, opts.chunk), .cancel = opts.cancel, .workers = 1 };
    // More workers than chunks would only spawn threads that find the queue empty.
    const chunks = (tasks.len + shared.cursor.chunk - 1) / shared.cursor.chunk;
    const n = @max(1, @min(want, max_threads, chunks));
    shared.workers = n;
    var handles: [max_threads]std.Thread = undefined;
    const first: usize = @intFromBool(opts.caller_works);
    var spawned: usize = 0;
    while (spawned + first < n) : (spawned += 1) {
        handles[spawned] = std.Thread.spawn(.{ .stack_size = opts.stack_size }, Shared(T).worker, .{ &shared, spawned + first }) catch break;
    }
    if (opts.caller_works or spawned == 0) shared.worker(0);
    for (handles[0..spawned]) |h| h.join();
    if (shared.canceled.load(.acquire)) return error.Canceled;
}

/// How an idle pool thread waits before sleeping on a futex.
pub const Spin = union(enum) {
    /// No spinning: sleep on the futex right away (event-only wake-up).
    none,
    /// Poll this many times, then sleep (PR #13 behaviour: 4096).
    iterations: u32,
    /// Poll for up to this many nanoseconds, then sleep.
    ns: u32,
    /// Per-thread budget in [0, max_ns]: doubled when the event arrived while
    /// spinning, halved when the thread had to sleep. Idle pools stop spinning.
    adaptive: struct { start_ns: u32 = 4_000, max_ns: u32 = 50_000 },
};

/// Options for `Pool.init`. All fields have defaults: `.{}` is valid.
pub const PoolOptions = struct {
    /// Total worker count including the thread that calls `run`. 0 = CPU count.
    threads: usize = 0,
    /// Stack size for the pool's threads (steps run on it).
    stack_size: usize = worker_stack_size,
    /// How idle threads wait for the next run (and the caller for the last worker).
    spin: Spin = default_spin,
    /// Wake only as many threads as there are chunks to share.
    cap_wake: bool = default_cap_wake,
    /// After spinning, yield the CPU this many times before sleeping.
    yields: u8 = default_yields,
};
const default_spin: Spin = .none;
const default_cap_wake = true;
const default_yields = 0;

/// Options for `Pool.run`. All fields have defaults: `.{}` is valid.
pub const RunOptions = struct {
    /// Tasks claimed from the shared queue at a time.
    chunk: usize = 64,
    /// Cooperative cancellation flag, checked between rounds.
    cancel: ?*const std.atomic.Value(bool) = null,
};

/// Long-lived worker threads for repeated `runParallel`-style runs.
///
/// `runParallel` spawns and joins its threads on every call; for many small
/// runs that is most of the cost. A `Pool` spawns them once. Between runs
/// idle threads sleep on a futex right away (no spinning); `run` wakes only as many threads as the run has chunks, so small runs wake nobody.
/// `run` works like `runParallel` with `caller_works = true`: the caller is worker 0.
///
/// Rules: a `Pool` must not move after `init` (threads hold a pointer to it);
/// one `run` at a time; a step must not call `run` on the same pool (it would
/// wait for itself), use `runParallel` for nested parallelism.
pub const Pool = struct {
    io: std.Io,
    handles: [max_threads]std.Thread = undefined,
    spawned: usize = 0,
    opts: PoolOptions = .{},
    gen: std.atomic.Value(u32) = .init(0),
    /// generation << 32 | participants wanted << 16 | slots claimed so far.
    claim: std.atomic.Value(u64) = .init(0),
    pending: std.atomic.Value(u32) = .init(0),
    stop: bool = false,
    caller_budget: u32 = 0,
    job_ctx: *anyopaque = undefined,
    job_fn: *const fn (*anyopaque, usize) void = undefined,

    pub fn init(p: *Pool, io: std.Io, opts: PoolOptions) void {
        p.* = .{ .io = io, .opts = opts };
        p.caller_budget = startBudget(opts.spin);
        const want = if (opts.threads == 0) (std.Thread.getCpuCount() catch 1) else opts.threads;
        const n = @max(1, @min(want, max_threads));
        while (p.spawned + 1 < n) : (p.spawned += 1) {
            p.handles[p.spawned] = std.Thread.spawn(.{ .stack_size = opts.stack_size }, loop, .{p}) catch break;
        }
    }

    pub fn deinit(p: *Pool) void {
        @atomicStore(bool, &p.stop, true, .release);
        _ = p.gen.fetchAdd(1, .release);
        p.io.futexWake(u32, &p.gen.raw, std.math.maxInt(u32));
        for (p.handles[0..p.spawned]) |h| h.join();
        p.* = undefined;
    }

    pub fn workers(p: *const Pool) usize {
        return p.spawned + 1;
    }

    pub fn run(p: *Pool, comptime T: type, tasks: []T, opts: RunOptions) Error!void {
        checkTask(T);
        var shared: Shared(T) = .{ .tasks = tasks, .cursor = .init(tasks.len, opts.chunk), .cancel = opts.cancel, .workers = 1 };
        const Thunk = struct {
            fn work(ctx: *anyopaque, index: usize) void {
                const s: *Shared(T) = @ptrCast(@alignCast(ctx));
                s.worker(index);
            }
        };
        var k: usize = p.spawned;
        if (p.opts.cap_wake) {
            const chunks = (tasks.len + shared.cursor.chunk - 1) / shared.cursor.chunk;
            k = @min(k, chunks -| 1);
        }
        shared.workers = k + 1;
        if (k == 0) {
            shared.worker(0);
            if (shared.canceled.load(.acquire)) return error.Canceled;
            return;
        }
        p.job_ctx = &shared;
        p.job_fn = Thunk.work;
        p.pending.store(@intCast(k), .monotonic);
        const g = p.gen.raw +% 1; // only `run` and `deinit` write `gen`
        p.claim.store(@as(u64, g) << 32 | @as(u64, k) << 16, .release);
        p.gen.store(g, .release);
        p.io.futexWake(u32, &p.gen.raw, @intCast(k));
        shared.worker(0);
        while (true) {
            const left = p.pending.load(.acquire);
            if (left == 0) break;
            if (p.waitChange(&p.pending, left, &p.caller_budget)) continue;
            p.io.futexWaitUncancelable(u32, &p.pending.raw, left);
        }
        if (shared.canceled.load(.acquire)) return error.Canceled;
    }

    fn startBudget(s: Spin) u32 {
        return switch (s) {
            .adaptive => |a| a.start_ns,
            else => 0,
        };
    }

    /// Spins (per policy) until `v` differs from `old`. True if it changed.
    fn waitChange(p: *Pool, v: *std.atomic.Value(u32), old: u32, budget: *u32) bool {
        const changed = switch (p.opts.spin) {
            .none => false,
            .iterations => |n| blk: {
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    std.atomic.spinLoopHint();
                    if (v.load(.acquire) != old) break :blk true;
                }
                break :blk false;
            },
            .ns => |ns| p.spinFor(v, old, ns),
            .adaptive => |a| blk: {
                const ok = p.spinFor(v, old, budget.*);
                budget.* = if (ok) @min(a.max_ns, @max(budget.* *| 2, 1_000)) else budget.* / 2;
                break :blk ok;
            },
        };
        if (changed) return true;
        var y: u8 = 0;
        while (y < p.opts.yields) : (y += 1) {
            std.Thread.yield() catch {};
            if (v.load(.acquire) != old) return true;
        }
        return false;
    }

    fn spinFor(p: *Pool, v: *std.atomic.Value(u32), old: u32, ns: u32) bool {
        if (ns == 0) return false;
        const t0 = std.Io.Timestamp.now(p.io, .awake).toNanoseconds();
        while (true) {
            for (0..32) |_| {
                std.atomic.spinLoopHint();
                if (v.load(.acquire) != old) return true;
            }
            if (std.Io.Timestamp.now(p.io, .awake).toNanoseconds() - t0 >= ns) return false;
        }
    }

    /// A participant slot in generation `g`, or null (run is full or already over).
    fn claimSlot(p: *Pool, g: u32) ?u32 {
        var c = p.claim.load(.acquire);
        while (true) {
            if (@as(u32, @truncate(c >> 32)) != g) return null;
            const n: u32 = @as(u16, @truncate(c));
            if (n >= @as(u16, @truncate(c >> 16))) return null;
            c = p.claim.cmpxchgWeak(c, c + 1, .acq_rel, .acquire) orelse return n;
        }
    }

    fn loop(p: *Pool) void {
        var seen: u32 = 0;
        var budget = startBudget(p.opts.spin);
        while (true) {
            var g = p.gen.load(.acquire);
            if (g == seen and !p.waitChange(&p.gen, seen, &budget)) {
                while (g == seen) {
                    p.io.futexWaitUncancelable(u32, &p.gen.raw, seen);
                    g = p.gen.load(.acquire);
                }
            }
            seen = p.gen.load(.acquire);
            if (@atomicLoad(bool, &p.stop, .acquire)) return;
            const s = p.claimSlot(seen) orelse continue;
            p.job_fn(p.job_ctx, s + 1);
            if (p.pending.fetchSub(1, .acq_rel) == 1) p.io.futexWake(u32, &p.pending.raw, 1);
        }
    }
};

/// Largest chunk `runParallel` steps through an index array (2 KiB of stack).
const max_indexed = 1024;

fn Shared(comptime T: type) type {
    return struct {
        tasks: []T,
        cursor: Cursor,
        cancel: ?*const std.atomic.Value(bool),
        workers: usize,
        canceled: std.atomic.Value(bool) = .init(false),

        // Tasks bigger than two words are not moved: a finished task leaves the
        // round by overwriting its u16 index instead of swapping the whole `T`.
        const use_indexed = @sizeOf(T) > 2 * @sizeOf(usize);

        /// `runAll` over at most `max_indexed` tasks without permuting them.
        fn runIndexed(tasks: []T, cancel: ?*const std.atomic.Value(bool)) Error!u64 {
            var idx: [max_indexed]u16 = undefined;
            for (idx[0..tasks.len], 0..) |*x, i| x.* = @intCast(i);
            var live = tasks.len;
            var steps: u64 = 0;
            while (live > 0) {
                if (cancel) |c| if (c.load(.acquire)) return error.Canceled;
                var i: usize = 0;
                while (i < live) {
                    steps += 1;
                    if (tasks[idx[i]].step() == .done) {
                        live -= 1;
                        idx[i] = idx[live];
                    } else i += 1;
                }
            }
            return steps;
        }

        fn worker(s: *@This(), index: usize) void {
            // A step may run `runParallel` itself; its worker must get this index back.
            const outer = current_worker;
            current_worker = index;
            defer current_worker = outer;
            while (s.cursor.claimTapered(s.workers)) |r| {
                const chunk = s.tasks[r.start..r.end];
                const res = if (use_indexed and chunk.len <= max_indexed) runIndexed(chunk, s.cancel) else runAll(T, chunk, s.cancel);
                _ = res catch {
                    s.canceled.store(true, .release);
                    return;
                };
            }
        }
    };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Counter = struct {
    id: u32,
    left: u32,
    acc: u64 = 0,
    thread: std.Thread.Id = 0,
    state: enum { start, run, finished } = .start,

    pub fn step(self: *Counter) Step {
        switch (self.state) {
            .start => {
                self.thread = std.Thread.getCurrentId();
                self.acc = self.id;
                self.state = .run;
                return .yield;
            },
            .run => {
                var i: u32 = 0;
                while (i < 64) : (i += 1) self.acc = self.acc *% 6364136223846793005 +% 1442695040888963407;
                self.left -= 1;
                if (self.left == 0) {
                    self.state = .finished;
                    return .done;
                }
                return .yield;
            },
            .finished => unreachable,
        }
    }
};

fn expected(id: u32, rounds: u32) u64 {
    var acc: u64 = id;
    for (0..rounds * 64) |_| acc = acc *% 6364136223846793005 +% 1442695040888963407;
    return acc;
}

test "runAll completes 10k tasks with interleaving" {
    const tasks = try testing.allocator.alloc(Counter, 10_000);
    defer testing.allocator.free(tasks);
    for (tasks, 0..) |*t, i| t.* = .{ .id = @intCast(i), .left = 1 + @as(u32, @intCast(i % 5)) };
    const steps = try runAll(Counter, tasks, null);
    var want: u64 = 0;
    for (0..tasks.len) |i| want += 2 + i % 5;
    try testing.expectEqual(want, steps);
    for (tasks) |t| {
        try testing.expect(t.state == .finished);
        try testing.expectEqual(expected(t.id, 1 + t.id % 5), t.acc);
    }
}

test "runParallel uses several threads and completes all tasks" {
    const tasks = try testing.allocator.alloc(Counter, 10_000);
    defer testing.allocator.free(tasks);
    for (tasks, 0..) |*t, i| t.* = .{ .id = @intCast(i), .left = 200 };
    try runParallel(Counter, tasks, .{ .threads = 4, .chunk = 16 });
    var ids: [4]std.Thread.Id = undefined;
    var distinct: usize = 0;
    for (tasks) |t| {
        try testing.expect(t.state == .finished);
        try testing.expectEqual(expected(t.id, 200), t.acc);
        if (std.mem.indexOfScalar(std.Thread.Id, ids[0..distinct], t.thread) == null) {
            try testing.expect(distinct < ids.len);
            ids[distinct] = t.thread;
            distinct += 1;
        }
    }
    if ((std.Thread.getCpuCount() catch 1) > 1) try testing.expect(distinct >= 2);
}

test "Cursor hands out every index once" {
    var c: Cursor = .init(10, 3);
    var seen: [10]u8 = @splat(0);
    while (c.claim()) |r| for (r.start..r.end) |i| {
        seen[i] += 1;
    };
    for (seen) |s| try testing.expectEqual(@as(u8, 1), s);
}

test "Cursor stays exhausted at any chunk size" {
    var empty: Cursor = .init(0, 0);
    try testing.expectEqual(@as(?Range, null), empty.claim());

    var zero: Cursor = .init(2, 0);
    try testing.expectEqual(@as(?Range, .{ .start = 0, .end = 1 }), zero.claim());
    try testing.expectEqual(@as(?Range, .{ .start = 1, .end = 2 }), zero.claim());
    try testing.expectEqual(@as(?Range, null), zero.claim());

    var huge: Cursor = .init(3, std.math.maxInt(usize) / 2 + 1);
    try testing.expectEqual(@as(?Range, .{ .start = 0, .end = 3 }), huge.claim());
    for (0..4) |_| try testing.expectEqual(@as(?Range, null), huge.claim());
}

const Claimer = struct {
    fn run(cursor: *Cursor, seen: []std.atomic.Value(u32)) void {
        while (cursor.claim()) |r| for (seen[r.start..r.end]) |*s| {
            _ = s.fetchAdd(1, .monotonic);
        };
    }
};

test "Cursor gives each index to one thread only" {
    const seen = try testing.allocator.alloc(std.atomic.Value(u32), 100_000);
    defer testing.allocator.free(seen);
    @memset(seen, .init(0));
    var cursor: Cursor = .init(seen.len, 7);
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Claimer.run, .{ &cursor, seen });
    for (threads) |t| t.join();
    for (seen) |*s| try testing.expectEqual(@as(u32, 1), s.load(.monotonic));
}

const Worked = struct {
    worker: ?usize = null,
    thread: std.Thread.Id = 0,

    pub fn step(self: *Worked) Step {
        self.worker = currentWorker();
        self.thread = std.Thread.getCurrentId();
        return .done;
    }
};

test "currentWorker numbers the workers and is null outside a run" {
    try testing.expectEqual(@as(?usize, null), currentWorker());
    var tasks: [256]Worked = @splat(.{});
    try runParallel(Worked, &tasks, .{ .threads = 4, .chunk = 1 });
    for (tasks) |t| {
        try testing.expect(t.worker.? < 4);
        if (t.thread == std.Thread.getCurrentId()) try testing.expectEqual(@as(?usize, 0), t.worker);
    }
    try testing.expectEqual(@as(?usize, null), currentWorker());
}

test "without caller_works every step stays off the calling thread" {
    var tasks: [256]Worked = @splat(.{});
    try runParallel(Worked, &tasks, .{ .threads = 3, .chunk = 1, .caller_works = false });
    for (tasks) |t| {
        try testing.expect(t.worker.? < 3);
        try testing.expect(t.thread != std.Thread.getCurrentId());
    }
}

const Deep = struct {
    reached: bool = false,

    pub fn step(self: *Deep) Step {
        var frame: [4 * worker_stack_size]u8 = undefined;
        @memset(&frame, 1);
        std.mem.doNotOptimizeAway(&frame);
        self.reached = true;
        return .done;
    }
};

test "stack_size reaches the workers" {
    var tasks: [8]Deep = @splat(.{});
    try runParallel(Deep, &tasks, .{ .threads = 2, .chunk = 1, .stack_size = 8 * worker_stack_size, .caller_works = false });
    for (tasks) |t| try testing.expect(t.reached);
}

const Nesting = struct {
    before: ?usize = null,
    after: ?usize = null,

    pub fn step(self: *Nesting) Step {
        self.before = currentWorker();
        var inner: [8]Worked = @splat(.{});
        runParallel(Worked, &inner, .{ .threads = 2, .chunk = 1 }) catch unreachable;
        self.after = currentWorker();
        return .done;
    }
};

test "a nested run gives the outer worker its index back" {
    var tasks: [8]Nesting = @splat(.{});
    try runParallel(Nesting, &tasks, .{ .threads = 2, .chunk = 1 });
    for (tasks) |t| {
        try testing.expect(t.before != null);
        try testing.expectEqual(t.before, t.after);
    }
}

const Forever = struct {
    n: u64 = 0,
    pub fn step(self: *Forever) Step {
        self.n += 1;
        return .yield;
    }
};

test "cancellation stops all workers and joins them" {
    var tasks: [256]Forever = @splat(.{});
    var cancel: std.atomic.Value(bool) = .init(false);
    const Stopper = struct {
        fn run(c: *std.atomic.Value(bool), t: []Forever) void {
            // wait until workers made progress, then cancel
            while (@atomicLoad(u64, &t[0].n, .monotonic) < 1000) std.atomic.spinLoopHint();
            c.store(true, .release);
        }
    };
    const th = try std.Thread.spawn(.{}, Stopper.run, .{ &cancel, &tasks });
    try testing.expectError(error.Canceled, runParallel(Forever, &tasks, .{ .threads = 3, .chunk = 256, .cancel = &cancel }));
    th.join();
    try testing.expectError(error.Canceled, runAll(Forever, &tasks, &cancel));
}

test "Pool runs many batches and shuts down" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var pool: Pool = undefined;
    pool.init(threaded.io(), .{ .threads = 4 });
    defer pool.deinit();
    var tasks: [256]Counter = undefined;
    for (0..200) |round| {
        for (&tasks, 0..) |*t, i| t.* = .{ .id = @intCast(i + round), .left = 3 };
        try pool.run(Counter, &tasks, .{ .chunk = 8 });
        for (tasks) |t| {
            try testing.expect(t.state == .finished);
            try testing.expectEqual(expected(t.id, 3), t.acc);
        }
    }
}

test "Pool.run observes cancel" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var pool: Pool = undefined;
    pool.init(threaded.io(), .{ .threads = 3 });
    defer pool.deinit();
    var cancel: std.atomic.Value(bool) = .init(true);
    var tasks: [64]Counter = undefined;
    for (&tasks, 0..) |*t, i| t.* = .{ .id = @intCast(i), .left = 5 };
    try testing.expectError(error.Canceled, pool.run(Counter, &tasks, .{ .cancel = &cancel }));
    cancel.store(false, .release);
    for (&tasks, 0..) |*t, i| t.* = .{ .id = @intCast(i), .left = 5 };
    try pool.run(Counter, &tasks, .{});
}

test "Pool with every spin mode, small and large runs" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const modes = [_]Spin{ .none, .{ .iterations = 64 }, .{ .ns = 1_000 }, .{ .adaptive = .{} } };
    for (modes) |mode| for ([_]bool{ false, true }) |cap| {
        var pool: Pool = undefined;
        pool.init(threaded.io(), .{ .threads = 4, .spin = mode, .cap_wake = cap });
        defer pool.deinit();
        for ([_]usize{ 1, 8, 9, 64, 300 }) |n| for (0..20) |round| {
            var tasks: [300]Counter = undefined;
            for (tasks[0..n], 0..) |*t, i| t.* = .{ .id = @intCast(i + round), .left = 3 };
            try pool.run(Counter, tasks[0..n], .{ .chunk = 8 });
            for (tasks[0..n]) |t| try testing.expectEqual(expected(t.id, 3), t.acc);
        };
    };
}

test "Cursor.claimTapered hands out every index once, shrinking to 1" {
    var c: Cursor = .init(1000, 64);
    var seen: [1000]bool = @splat(false);
    var last: usize = 64;
    while (c.claimTapered(4)) |r| {
        try testing.expect(r.end > r.start and r.end - r.start <= 64);
        last = r.end - r.start;
        for (seen[r.start..r.end]) |*b| {
            try testing.expect(!b.*);
            b.* = true;
        }
    }
    try testing.expectEqual(@as(usize, 1), last);
    for (seen) |b| try testing.expect(b);
}
