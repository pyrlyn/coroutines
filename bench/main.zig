//! Benchmarks: `zig build bench` (ReleaseFast) or `zig-out/bin/bench [suite]`.
//! Suites: switch, spawn, procs, all (default). Every measured variant runs in
//! its own child process (`bench variant <name>`), so peak RSS, page faults and
//! context switches are attributed to that variant only.
const std = @import("std");
const builtin = @import("builtin");
const coro = @import("coroutines");
const sm = coro.state_machine;
const Io = std.Io;

const is_windows = builtin.os.tag == .windows;

// ------------------------------------------------------------ workload

/// One "small task": 4 slices of 256 xorshift64 rounds (~1k rounds total).
/// xorshift is not affine, so the optimizer cannot fold the loop away.
const slices = 4;
const iters_per_slice = 256;

fn sliceWork(acc: u64) u64 {
    var x = acc | 1;
    for (0..iters_per_slice) |_| {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
    }
    return x;
}

fn taskSequential(id: u64) u64 {
    var x = id;
    for (0..slices) |_| x = sliceWork(x);
    return x;
}

const SmTask = struct {
    acc: u64,
    left: u8 = slices,
    out: *std.atomic.Value(u64),
    pub fn step(t: *SmTask) sm.Step {
        t.acc = sliceWork(t.acc);
        t.left -= 1;
        if (t.left == 0) {
            _ = t.out.fetchAdd(t.acc, .monotonic);
            return .done;
        }
        return .yield;
    }
};

fn ioTask(out: *std.atomic.Value(u64), id: usize) Io.Cancelable!void {
    _ = out.fetchAdd(taskSequential(id), .monotonic);
}

// ------------------------------------------------------------ counting allocator

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
};

// ------------------------------------------------------------ resource usage

const Usage = struct {
    maxrss_kb: u64 = 0,
    minflt: u64 = 0,
    majflt: u64 = 0,
    nvcsw: u64 = 0,
    nivcsw: u64 = 0,
    cpu_us: u64 = 0, // user + sys
};

const PROCESS_MEMORY_COUNTERS = extern struct {
    cb: u32,
    PageFaultCount: u32,
    PeakWorkingSetSize: usize,
    WorkingSetSize: usize,
    QuotaPeakPagedPoolUsage: usize,
    QuotaPagedPoolUsage: usize,
    QuotaPeakNonPagedPoolUsage: usize,
    QuotaNonPagedPoolUsage: usize,
    PagefileUsage: usize,
    PeakPagefileUsage: usize,
};
extern "kernel32" fn K32GetProcessMemoryInfo(h: std.os.windows.HANDLE, c: *PROCESS_MEMORY_COUNTERS, cb: u32) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) std.os.windows.HANDLE;

fn usage(children: bool) Usage {
    if (is_windows) {
        if (children) return .{};
        var c: PROCESS_MEMORY_COUNTERS = undefined;
        c.cb = @sizeOf(PROCESS_MEMORY_COUNTERS);
        if (K32GetProcessMemoryInfo(GetCurrentProcess(), &c, c.cb) == .FALSE) return .{};
        return .{ .maxrss_kb = c.PeakWorkingSetSize / 1024, .minflt = c.PageFaultCount };
    }
    var ru: std.c.rusage = undefined;
    _ = std.c.getrusage(if (children) std.c.rusage.CHILDREN else std.c.rusage.SELF, &ru);
    const rss: u64 = @intCast(ru.maxrss);
    return .{
        // Linux reports KiB, macOS bytes.
        .maxrss_kb = if (builtin.os.tag.isDarwin()) rss / 1024 else rss,
        .minflt = @intCast(ru.minflt),
        .majflt = @intCast(ru.majflt),
        .nvcsw = @intCast(ru.nvcsw),
        .nivcsw = @intCast(ru.nivcsw),
        .cpu_us = @as(u64, @intCast(ru.utime.sec)) * 1_000_000 + @as(u64, @intCast(ru.utime.usec)) +
            @as(u64, @intCast(ru.stime.sec)) * 1_000_000 + @as(u64, @intCast(ru.stime.usec)),
    };
}

fn now(io: Io) i96 {
    return Io.Timestamp.now(io, .awake).toNanoseconds();
}

// ------------------------------------------------------------ variants (run in child)

const Result = struct {
    name: []const u8,
    ops: u64,
    ns: i96,
    /// wall time of the whole variant incl. setup/teardown (same interval as cpu)
    wall_all_ns: i96 = 0,
    allocs: u64 = 0,
    alloc_bytes: u64 = 0,
    threads: usize = 1,
    procs: usize = 1,
    spawn_ns: i96 = 0,
    check: u64 = 0,
    self: Usage = .{},
    children: Usage = .{},
};

var n_tasks: usize = 10_000;
const switch_steps = 10_000_000;
const handoffs = 200_000;

fn cpuCount() usize {
    return std.Thread.getCpuCount() catch 1;
}

const Ping = struct {
    left: u64,
    pub fn step(p: *Ping) sm.Step {
        p.left -= 1;
        std.mem.doNotOptimizeAway(p);
        return if (p.left == 0) .done else .yield;
    }
};

fn pong(io: Io, a: *Io.Queue(u32), b: *Io.Queue(u32), n: usize) Io.Cancelable!void {
    for (0..n) |_| {
        const v = a.getOne(io) catch return;
        b.putOne(io, v + 1) catch return;
    }
}

fn runVariant(init: std.process.Init, name: []const u8, extra: []const [:0]const u8) !Result {
    const io = init.io;
    var counting: Counting = .{ .child = std.heap.page_allocator };
    const ca = counting.allocator();
    var out: std.atomic.Value(u64) = .init(0);
    const all0 = now(io);
    const cpu0 = usage(false).cpu_us;
    var extra_args = extra;
    if (extra_args.len > 0 and std.mem.startsWith(u8, extra_args[0], "t=")) {
        n_tasks = try std.fmt.parseInt(usize, extra_args[0][2..], 10);
        extra_args = extra_args[1..];
    }
    var r: Result = .{ .name = name, .ops = n_tasks, .ns = 0 };

    if (std.mem.eql(u8, name, "sm-switch")) {
        // One task, many yields: cost of one step call through the scheduler.
        var t = [1]Ping{.{ .left = switch_steps }};
        const t0 = now(io);
        const steps = try sm.runAll(Ping, &t, null);
        r.ns = now(io) - t0;
        r.ops = steps;
    } else if (std.mem.eql(u8, name, "io-switch")) {
        // Ping-pong between two Io tasks over two 1-slot queues: each
        // handoff is a cross-task wake-up (thread handoff under Io.Threaded).
        var threaded: Io.Threaded = .init(ca, .{});
        defer threaded.deinit();
        const tio = threaded.io();
        var ba: [1]u32 = undefined;
        var bb: [1]u32 = undefined;
        var qa: Io.Queue(u32) = .init(&ba);
        var qb: Io.Queue(u32) = .init(&bb);
        const a0 = counting.allocs.load(.monotonic);
        const t0 = now(io);
        var f = try tio.concurrent(pong, .{ tio, &qa, &qb, handoffs });
        var v: u32 = 0;
        for (0..handoffs) |_| {
            try qa.putOne(tio, v);
            v = try qb.getOne(tio);
        }
        try f.await(tio);
        r.ns = now(io) - t0;
        r.ops = handoffs * 2;
        r.allocs = counting.allocs.load(.monotonic) - a0;
        r.threads = 2;
        r.check = v;
    } else if (std.mem.eql(u8, name, "sequential")) {
        const t0 = now(io);
        var acc: u64 = 0;
        for (0..n_tasks) |i| acc +%= taskSequential(i);
        std.mem.doNotOptimizeAway(acc);
        r.ns = now(io) - t0;
        r.check = acc;
    } else if (std.mem.eql(u8, name, "sm-1thread") or std.mem.eql(u8, name, "sm-parallel")) {
        const parallel = name[3] == 'p';
        const t0 = now(io);
        const tasks = try ca.alloc(SmTask, n_tasks); // one allocation for all tasks
        for (tasks, 0..) |*t, i| t.* = .{ .acc = i, .out = &out };
        if (parallel) {
            r.threads = cpuCount();
            try sm.runParallel(SmTask, tasks, .{ .threads = r.threads, .chunk = 256 });
        } else _ = try sm.runAll(SmTask, tasks, null);
        r.ns = now(io) - t0;
        ca.free(tasks);
        r.check = out.load(.monotonic);
    } else if (std.mem.eql(u8, name, "io-group")) {
        var threaded: Io.Threaded = .init(ca, .{});
        defer threaded.deinit();
        const tio = threaded.io();
        r.threads = cpuCount();
        const t0 = now(io);
        var g: Io.Group = .init;
        coro.io.spawnEach(tio, &g, n_tasks, ioTask, &out);
        try g.await(tio);
        r.ns = now(io) - t0;
        r.check = out.load(.monotonic);
    } else if (std.mem.eql(u8, name, "procs2") or std.mem.eql(u8, name, "procs")) {
        // N OS processes (this binary in worker mode) splitting the tasks.
        // Each child's peak RSS comes from its own wait4() rusage and is summed.
        const n: usize = if (name.len == 6) 2 else if (extra_args.len > 0) try std.fmt.parseInt(usize, extra_args[0], 10) else 2;
        const exe = try std.process.executablePathAlloc(io, init.gpa);
        defer init.gpa.free(exe);
        const kids = try init.gpa.alloc(std.process.Child, n);
        defer init.gpa.free(kids);
        const bounds = try init.gpa.alloc([2][24]u8, n);
        defer init.gpa.free(bounds);
        r.procs = n + 1;
        r.name = try std.fmt.allocPrint(init.arena.allocator(), "procs-{d}", .{n});
        const t0 = now(io);
        for (kids, bounds, 0..) |*k, *bd, i| {
            const lo = try std.fmt.bufPrint(&bd[0], "{d}", .{n_tasks * i / n});
            const hi = try std.fmt.bufPrint(&bd[1], "{d}", .{n_tasks * (i + 1) / n});
            k.* = try std.process.spawn(io, .{
                .argv = &.{ exe, "worker", lo, hi },
                .stdout = .pipe,
                .request_resource_usage_statistics = true,
            });
        }
        r.spawn_ns = now(io) - t0;
        var rss_sum: u64 = 0;
        for (kids) |*k| {
            var buf: [64]u8 = undefined;
            var rd = k.stdout.?.reader(io, &buf);
            const line = (try rd.interface.takeDelimiter('\n')) orelse "0";
            r.check +%= try std.fmt.parseInt(u64, std.mem.trim(u8, line, " \r"), 10);
            _ = try k.wait(io);
            rss_sum += (k.resource_usage_statistics.getMaxRss() orelse 0) / 1024;
        }
        r.ns = now(io) - t0;
        r.children = usage(true);
        r.children.maxrss_kb = rss_sum;
    } else if (std.mem.eql(u8, name, "sm-fine")) {
        // sm-parallel with chunk = 1: one claim per task, the queue is hot.
        r.threads = cpuCount();
        const t0 = now(io);
        const tasks = try ca.alloc(SmTask, n_tasks);
        for (tasks, 0..) |*t, i| t.* = .{ .acc = i, .out = &out };
        try sm.runParallel(SmTask, tasks, .{ .threads = r.threads, .chunk = 1 });
        r.ns = now(io) - t0;
        ca.free(tasks);
        r.check = out.load(.monotonic);
    } else {
        return error.UnknownVariant;
    }
    if (r.allocs == 0) {
        r.allocs = counting.allocs.load(.monotonic);
        r.alloc_bytes = counting.bytes.load(.monotonic);
    } else r.alloc_bytes = counting.bytes.load(.monotonic);
    r.self = usage(false);
    r.self.cpu_us -= cpu0; // CPU spent inside this function only
    r.wall_all_ns = now(io) - all0;
    return r;
}

fn emit(w: *Io.Writer, r: Result) !void {
    try w.print("{s} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d}\n", .{
        r.name,             r.ops,            r.ns,             r.allocs,         r.alloc_bytes,
        r.threads,          r.procs,          r.spawn_ns,       r.check,          r.self.maxrss_kb,
        r.self.minflt,      r.self.majflt,    r.self.nvcsw,     r.self.nivcsw,    r.children.maxrss_kb,
        r.children.minflt,  r.children.nvcsw, r.children.nivcsw,  r.self.cpu_us,     r.children.cpu_us, r.wall_all_ns,
    });
}

fn parse(line: []const u8, name_buf: []u8) !Result {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    const name = it.next() orelse return error.Bad;
    @memcpy(name_buf[0..name.len], name);
    var v: [20]i128 = undefined;
    for (&v) |*x| x.* = try std.fmt.parseInt(i128, it.next() orelse return error.Bad, 10);
    const u = struct {
        fn f(x: i128) u64 {
            return @intCast(x);
        }
    }.f;
    return .{
        .name = name_buf[0..name.len], .ops = u(v[0]), .ns = @intCast(v[1]), .allocs = u(v[2]), .alloc_bytes = u(v[3]),
        .wall_all_ns = @intCast(v[19]), .threads = @intCast(v[4]), .procs = @intCast(v[5]), .spawn_ns = @intCast(v[6]), .check = u(v[7]),
        .self = .{ .maxrss_kb = u(v[8]), .minflt = u(v[9]), .majflt = u(v[10]), .nvcsw = u(v[11]), .nivcsw = u(v[12]), .cpu_us = u(v[17]) },
        .children = .{ .maxrss_kb = u(v[13]), .minflt = u(v[14]), .nvcsw = u(v[15]), .nivcsw = u(v[16]), .cpu_us = u(v[18]) },
    };
}

// ------------------------------------------------------------ driver

const Suite = struct { name: []const u8, title: []const u8, variants: []const []const u8 };
const suites = [_]Suite{
    .{ .name = "switch", .title = "Switch cost", .variants = &.{ "sm-switch", "io-switch" } },
    .{ .name = "spawn", .title = "Spawn and run 10,000 small tasks", .variants = &.{ "sm-1thread", "sm-parallel", "io-group" } },
    .{ .name = "procs", .title = "Processes vs coroutines, same 10,000-task workload", .variants = &.{ "sequential", "procs2", "sm-1thread", "sm-parallel", "io-group" } },
};

const reps = 5;

fn mb(kb: u64) f64 {
    return @as(f64, @floatFromInt(kb)) / 1024.0;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var obuf: [4096]u8 = undefined;
    var fw = Io.File.stdout().writerStreaming(io, &obuf);
    const w = &fw.interface;
    defer w.flush() catch {};

    if (args.len >= 4 and std.mem.eql(u8, args[1], "worker")) {
        const a = try std.fmt.parseInt(u64, args[2], 10);
        const b = try std.fmt.parseInt(u64, args[3], 10);
        var acc: u64 = 0;
        for (a..b) |i| acc +%= taskSequential(i);
        try w.print("{d}\n", .{acc});
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "variant")) {
        // warm-up-free single shot; the driver repeats and takes the median
        try emit(w, try runVariant(init, args[2], args[3..]));
        return;
    }

    const which: []const u8 = if (args.len >= 2) args[1] else "all";
    const exe = try std.process.executablePathAlloc(io, init.gpa);
    defer init.gpa.free(exe);

    const header =
        \\| variant | ops | total ns | ns/op | allocs | alloc bytes | threads | procs | spawn ns | peak RSS MB (self) | peak RSS MB (children, sum) | RSS MB total | minflt | majflt | vol ctxsw | invol ctxsw | child minflt | child vol ctxsw | child invol ctxsw |
        \\|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
        \\
    ;
    for (suites) |s| {
        if (!std.mem.eql(u8, which, "all") and !std.mem.eql(u8, which, s.name)) continue;
        try w.print("## {s}\n\n", .{s.title});
        try w.print("Median of {d} runs; each run is a fresh process. RSS = peak resident set of that process.\n\n", .{reps});
        try w.writeAll(header);
        for (s.variants) |v| try row(w, try measure(init, exe, &.{v}, reps));
        try w.print("\n", .{});
    }

    if (std.mem.eql(u8, which, "all") or std.mem.eql(u8, which, "bytasks")) {
        const hreps = 3;
        const cpus = cpuCount();
        try w.print("## Three backends by task count N\n\n", .{});
        try w.print("Median of {d} runs, each a fresh process. processes = min(N, {d} CPUs) worker processes. RSS = parent + sum of children peak RSS. CPU % = (user + sys CPU time of the variant and its children, from getrusage) / wall time of the same interval (incl. setup such as thread pool and allocation); 100% = one core busy. wall ms = timed region only.\n\n", .{ hreps, cpus });
        try w.writeAll("| variant | N | wall ms | RSS MB | CPU % |\n|---|---:|---:|---:|---:|\n");
        for ([_]usize{ 16, 64, 255, 256, 257, 1024, 10_000 }) |n| {
            var tb: [24]u8 = undefined;
            const targ = try std.fmt.bufPrint(&tb, "t={d}", .{n});
            var pb: [24]u8 = undefined;
            const parg = try std.fmt.bufPrint(&pb, "{d}", .{@min(n, cpus)});
            const rows = [_]struct { label: []const u8, args: []const []const u8 }{
                .{ .label = "state machine", .args = &.{ "sm-parallel", targ } },
                .{ .label = "Io", .args = &.{ "io-group", targ } },
                .{ .label = "processes", .args = &.{ "procs", targ, parg } },
            };
            for (rows) |rw| {
                const r = try measure(init, exe, rw.args, hreps);
                const wall_ns: f64 = @floatFromInt(r.ns);
                const all_ns: f64 = @floatFromInt(r.wall_all_ns);
                const cpu_ns: f64 = @floatFromInt((r.self.cpu_us + r.children.cpu_us) * 1000);
                try w.print("| {s} | {d} | {d:.2} | {d:.1} | {d:.0} |\n", .{
                    rw.label, n, wall_ns / 1e6, mb(r.self.maxrss_kb + r.children.maxrss_kb), 100 * cpu_ns / all_ns,
                });
            }
            try w.flush();
        }
        try w.print("\n", .{});
    }

    if (std.mem.eql(u8, which, "all") or std.mem.eql(u8, which, "sweep")) {
        // Memory cap: 50% of available RAM (MEM_AVAILABLE_MB, set by bench/run.sh).
        const avail_mb: u64 = if (init.environ_map.get("MEM_AVAILABLE_MB")) |m| std.fmt.parseInt(u64, m, 10) catch 4096 else 4096;
        const cap_kb = avail_mb * 1024 / 2;
        const sweep_reps = 3;
        try w.print("## Process sweep: N worker processes vs coroutines, same 10,000 tasks\n\n", .{});
        try w.print("Median of {d} runs. N doubles from 1 while N <= 1024 and the projected total RSS of the next N stays under 50% of available RAM ({d} MB of {d} MB). Children RSS = sum of each child's own peak RSS (wait4 rusage per child).\n\n", .{ sweep_reps, cap_kb / 1024, avail_mb });
        try w.writeAll(header);
        var n: usize = 1;
        while (n <= 1024) : (n *= 2) {
            var nb: [16]u8 = undefined;
            const r = measure(init, exe, &.{ "procs", try std.fmt.bufPrint(&nb, "{d}", .{n}) }, sweep_reps) catch |e| {
                try w.print("\nStopped at N = {d}: {t} (OS limit, see `ulimit -n` / `ulimit -u`).\n\n", .{ n, e });
                break;
            };
            try row(w, r);
            try w.flush();
            const per_child = r.children.maxrss_kb / n;
            if (r.self.maxrss_kb + per_child * n * 2 > cap_kb) {
                try w.print("\nStopped: next N would exceed the memory cap.\n", .{});
                break;
            }
        }
        for ([_][]const u8{ "sm-parallel", "io-group" }) |v| try row(w, try measure(init, exe, &.{v}, sweep_reps));
        try w.print("\n", .{});
    }
}

fn measure(init: std.process.Init, exe: []const u8, vargs: []const []const u8, comptime n: usize) !Result {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try arena.alloc([]const u8, vargs.len + 2);
    argv[0] = exe;
    argv[1] = "variant";
    @memcpy(argv[2..], vargs);
    var runs: [n]Result = undefined;
    for (&runs) |*r| {
        const res = try std.process.run(init.gpa, io, .{ .argv = argv });
        defer init.gpa.free(res.stdout);
        defer init.gpa.free(res.stderr);
        const nb = try arena.alloc(u8, 32);
        r.* = parse(std.mem.trim(u8, res.stdout, " \r\n"), nb) catch {
            std.debug.print("variant {s} failed: {s}\n", .{ vargs[0], res.stderr });
            return error.VariantFailed;
        };
    }
    std.mem.sortUnstable(Result, &runs, {}, struct {
        fn lt(_: void, a: Result, b: Result) bool {
            return a.ns < b.ns;
        }
    }.lt);
    return runs[n / 2];
}

fn row(w: *Io.Writer, r: Result) !void {
    const nsop = @as(f64, @floatFromInt(r.ns)) / @as(f64, @floatFromInt(r.ops));
    try w.print("| {s} | {d} | {d} | {d:.1} | {d} | {d} | {d} | {d} | {d} | {d:.1} | {d:.1} | {d:.1} | {d} | {d} | {d} | {d} | {d} | {d} | {d} |\n", .{
        r.name,            r.ops,                r.ns,                     nsop,
        r.allocs,          r.alloc_bytes,        r.threads,                r.procs,
        r.spawn_ns,        mb(r.self.maxrss_kb), mb(r.children.maxrss_kb), mb(r.self.maxrss_kb + r.children.maxrss_kb),
        r.self.minflt,     r.self.majflt,        r.self.nvcsw,             r.self.nivcsw,
        r.children.minflt, r.children.nvcsw,     r.children.nivcsw,
    });
}
