//! Hybrid backend: OS processes for small batches, `std.Io` coroutines for
//! large ones.
//!
//! `run` executes `task(ctx, i)` for every `i` in `0..n` and returns the
//! wrapping sum of the results (the same reduction for both modes).
//!
//! * `n <= threshold` → `.processes`: re-executes the current binary
//!   `processes` times, each child computing a contiguous range and printing
//!   its partial sum. The binary must call `workerMain` at the start of
//!   `main` so children can recognise worker mode.
//! * `n >  threshold` → `.io`: one `Io.Group` task per index on the given `Io`.
//!
//! Default threshold 256: in `bench/results/sweep-darwin-arm64.md`, from
//! N = 256 processes on, `io-group` beats processes on wall time on macOS.
const std = @import("std");
const Io = std.Io;
const coro_io = @import("io.zig");

pub const default_threshold = 256;
pub const worker_flag = "--coroutines-hybrid-worker";

pub const Mode = enum { processes, io };

pub const Options = struct {
    /// Task count above which the hybrid switches from processes to Io.
    threshold: usize = default_threshold,
    /// Worker processes in `.processes` mode. 0 = CPU count (capped at n).
    processes: usize = 0,
};

pub const Result = struct {
    sum: u64,
    mode: Mode,
    /// `.processes` mode: sum of every worker's own peak RSS in bytes
    /// (0 where the OS does not report it, and in `.io` mode).
    children_peak_rss_bytes: u64 = 0,
};

/// Pure decision function: processes up to and including `threshold`.
pub fn chooseMode(n: usize, threshold: usize) Mode {
    return if (n > threshold) .io else .processes;
}

pub fn run(
    io: Io,
    gpa: std.mem.Allocator,
    n: usize,
    ctx: anytype,
    comptime task: fn (@TypeOf(ctx), usize) u64,
    opts: Options,
) !Result {
    return switch (chooseMode(n, opts.threshold)) {
        .io => .{ .sum = try runIo(io, n, ctx, task), .mode = .io },
        .processes => blk: {
            var rss: u64 = 0;
            const sum = try runProcesses(io, gpa, n, opts.processes, &rss);
            break :blk .{ .sum = sum, .mode = .processes, .children_peak_rss_bytes = rss };
        },
    };
}

fn runIo(io: Io, n: usize, ctx: anytype, comptime task: fn (@TypeOf(ctx), usize) u64) Io.Cancelable!u64 {
    const Shared = struct {
        ctx: @TypeOf(ctx),
        sum: std.atomic.Value(u64) = .init(0),
        fn one(s: *@This(), i: usize) Io.Cancelable!void {
            _ = s.sum.fetchAdd(task(s.ctx, i), .monotonic);
        }
    };
    var shared: Shared = .{ .ctx = ctx };
    var group: Io.Group = .init;
    coro_io.spawnEach(io, &group, n, Shared.one, &shared);
    try group.await(io);
    return shared.sum.load(.monotonic);
}

fn runProcesses(io: Io, gpa: std.mem.Allocator, n: usize, processes: usize, rss: *u64) !u64 {
    if (n == 0) return 0;
    const want = if (processes == 0) (std.Thread.getCpuCount() catch 1) else processes;
    const p = @max(1, @min(want, n));
    const exe = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(exe);
    const kids = try gpa.alloc(std.process.Child, p);
    defer gpa.free(kids);
    const bounds = try gpa.alloc([2][24]u8, p);
    defer gpa.free(bounds);
    var started: usize = 0;
    errdefer for (kids[0..started]) |*k| {
        k.kill(io);
    };
    for (kids, bounds, 0..) |*k, *bd, i| {
        const lo = try std.fmt.bufPrint(&bd[0], "{d}", .{n * i / p});
        const hi = try std.fmt.bufPrint(&bd[1], "{d}", .{n * (i + 1) / p});
        k.* = try std.process.spawn(io, .{ .argv = &.{ exe, worker_flag, lo, hi }, .stdout = .pipe, .request_resource_usage_statistics = true });
        started += 1;
    }
    var sum: u64 = 0;
    var failed = false;
    for (kids) |*k| {
        var buf: [64]u8 = undefined;
        var rd = k.stdout.?.reader(io, &buf);
        const line = rd.interface.takeDelimiter('\n') catch null;
        if (line) |l| {
            sum +%= std.fmt.parseInt(u64, std.mem.trim(u8, l, " \r"), 10) catch blk: {
                failed = true;
                break :blk 0;
            };
        } else failed = true;
        const term = try k.wait(io);
        if (!term.success()) failed = true;
        rss.* += k.resource_usage_statistics.getMaxRss() orelse 0;
    }
    started = 0;
    if (failed) return error.WorkerFailed;
    return sum;
}

/// Call first thing in `main`. Returns true if this process is a hybrid
/// worker; it has then computed its range, printed the partial sum, and the
/// caller should return.
pub fn workerMain(io: Io, args: []const [:0]const u8, ctx: anytype, comptime task: fn (@TypeOf(ctx), usize) u64) !bool {
    if (args.len < 4 or !std.mem.eql(u8, args[1], worker_flag)) return false;
    const lo = try std.fmt.parseInt(usize, args[2], 10);
    const hi = try std.fmt.parseInt(usize, args[3], 10);
    var sum: u64 = 0;
    for (lo..hi) |i| sum +%= task(ctx, i);
    var buf: [64]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(io, &buf);
    try w.interface.print("{d}\n", .{sum});
    try w.interface.flush();
    return true;
}

test "chooseMode: below, at and above the threshold" {
    try std.testing.expectEqual(Mode.processes, chooseMode(0, 256));
    try std.testing.expectEqual(Mode.processes, chooseMode(255, 256));
    try std.testing.expectEqual(Mode.processes, chooseMode(256, 256));
    try std.testing.expectEqual(Mode.io, chooseMode(257, 256));
    try std.testing.expectEqual(Mode.io, chooseMode(10_000, 256));
    try std.testing.expectEqual(Mode.io, chooseMode(1, 0));
    try std.testing.expectEqual(@as(usize, 256), (Options{}).threshold);
}

fn square(_: void, i: usize) u64 {
    return @as(u64, i) * i;
}

test "Io mode above the threshold computes the same sum" {
    var threaded: Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const r = try run(threaded.io(), std.testing.allocator, 1000, {}, square, .{ .threshold = 10 });
    try std.testing.expectEqual(Mode.io, r.mode);
    var want: u64 = 0;
    for (0..1000) |i| want +%= square({}, i);
    try std.testing.expectEqual(want, r.sum);
}
