//! End-to-end test for the hybrid backend (run by `zig build test`).
//! The processes mode re-executes this binary, which a unit-test binary
//! cannot do, hence a separate executable.
const std = @import("std");
const hybrid = @import("coroutines").hybrid;

fn task(_: void, i: usize) u64 {
    var x: u64 = i | 1;
    for (0..64) |_| {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
    }
    return x;
}

fn expected(n: usize) u64 {
    var s: u64 = 0;
    for (0..n) |i| s +%= task({}, i);
    return s;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (try hybrid.workerMain(io, args, {}, task)) return;

    const Case = struct { n: usize, threshold: usize, mode: hybrid.Mode };
    const cases = [_]Case{
        .{ .n = 0, .threshold = 256, .mode = .processes },
        .{ .n = 1, .threshold = 256, .mode = .processes },
        .{ .n = 255, .threshold = 256, .mode = .processes },
        .{ .n = 256, .threshold = 256, .mode = .processes }, // exactly at threshold
        .{ .n = 257, .threshold = 256, .mode = .io },
        .{ .n = 10_000, .threshold = 256, .mode = .io },
        .{ .n = 100, .threshold = 99, .mode = .io }, // custom threshold
        .{ .n = 100, .threshold = 100, .mode = .processes },
    };
    for (cases) |c| {
        const r = try hybrid.run(io, init.gpa, c.n, {}, task, .{ .threshold = c.threshold, .processes = 4 });
        if (r.mode != c.mode or r.sum != expected(c.n)) {
            std.debug.print("FAIL n={d} threshold={d}: mode {t} (want {t}), sum {d} (want {d})\n", .{ c.n, c.threshold, r.mode, c.mode, r.sum, expected(c.n) });
            return error.TestFailed;
        }
    }
    // Same answer from both modes for the same n (switching does not change results).
    const a = try hybrid.run(io, init.gpa, 300, {}, task, .{ .threshold = 300 });
    const b = try hybrid.run(io, init.gpa, 300, {}, task, .{ .threshold = 299 });
    if (a.mode != .processes or b.mode != .io or a.sum != b.sum) return error.TestFailed;
    std.debug.print("hybrid e2e: {d} cases OK\n", .{cases.len + 1});
}
