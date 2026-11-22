//! "Before": the same workloads on pyrlyn/coroutines main (cf6d8a7), i.e. std.Io
//! on Io.Threaded (Group.async / Future.await / Io.Queue). Multi-thread only.
const std = @import("std");
const coro = @import("coroutines");
const Io = std.Io;

const JOIN_ONE_N = 200_000;
const SPAWN_N = 1_000_000;
const PINGPONG = 100_000;
const FANIN_N = 200_000;
const FANIN_CAP = 1024;
const SKEW_N = 10_000;

var io_g: Io = undefined;
fn now() i96 {
    return Io.Timestamp.now(io_g, .awake).toNanoseconds();
}
fn emit(name: []const u8, ns: i96, ops: u64) void {
    std.debug.print("{s} {d:.3} 0 0\n", .{ name, @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(ops)) });
}
fn tiny(i: u64) u64 {
    return i *% 3 +% 1;
}
var out: []u64 = undefined;
fn tinyG(i: usize) Io.Cancelable!void {
    out[i] = i *% 3 +% 1;
}
fn lcg(iters: u64, seed: u64) u64 {
    var x = seed;
    var i: u64 = 0;
    while (i < iters) : (i += 1) x = x *% 6364136223846793005 +% 1442695040888963407;
    return x;
}
fn work(i: usize) Io.Cancelable!void {
    out[i] = lcg(if (i % 100 == 0) 100_000 else 1_000, i);
}
fn pong(io: Io, a: *Io.Queue(u32), b: *Io.Queue(u32)) Io.Cancelable!void {
    for (0..PINGPONG) |_| {
        const v = a.getOne(io) catch return;
        b.putOne(io, v + 1) catch return;
    }
}
fn sender(io: Io, q: *Io.Queue(u64), v: u64) Io.Cancelable!void {
    q.putOne(io, v) catch {};
}

pub fn main(init: std.process.Init) !void {
    io_g = init.io;
    const gpa = std.heap.smp_allocator;
    var threaded: Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const tio = threaded.io();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const which: []const u8 = if (args.len > 1) args[1] else "all";
    const all = std.mem.eql(u8, which, "all");
    out = try gpa.alloc(u64, SPAWN_N);

    if (all or std.mem.eql(u8, which, "joinone")) {
        const t0 = now();
        var s: u64 = 0;
        for (0..JOIN_ONE_N) |i| {
            var f = try tio.concurrent(tiny, .{@as(u64, i)});
            s +%= f.await(tio);
        }
        std.mem.doNotOptimizeAway(s);
        emit("spawnjoin1_before_mt", now() - t0, JOIN_ONE_N);
    }
    if (all or std.mem.eql(u8, which, "spawn")) {
        const t0 = now();
        var g: Io.Group = .init;
        for (0..SPAWN_N) |i| g.async(tio, tinyG, .{i});
        try g.await(tio);
        emit("spawn_before_mt", now() - t0, SPAWN_N);
    }
    if (all or std.mem.eql(u8, which, "pingpong")) {
        var ba: [1]u32 = undefined;
        var bb: [1]u32 = undefined;
        var qa: Io.Queue(u32) = .init(&ba);
        var qb: Io.Queue(u32) = .init(&bb);
        const t0 = now();
        var f = try tio.concurrent(pong, .{ tio, &qa, &qb });
        var v: u32 = 0;
        for (0..PINGPONG) |_| {
            try qa.putOne(tio, v);
            v = try qb.getOne(tio);
        }
        try f.await(tio);
        std.mem.doNotOptimizeAway(v);
        emit("pingpong_before_mt", now() - t0, PINGPONG);
    }
    if (all or std.mem.eql(u8, which, "fanin")) {
        // Senders that find the queue full block their OS thread; with
        // Group.async a task that gets no thread runs inline on the caller
        // (the receiver), which would deadlock, so use concurrent() and count
        // the sends that could not get a thread.
        const buf = try gpa.alloc(u64, FANIN_CAP);
        var q: Io.Queue(u64) = .init(buf);
        var g: Io.Group = .init;
        const t0 = now();
        var spawned: usize = 0;
        var s: u64 = 0;
        var got: usize = 0;
        var i: usize = 0;
        while (i < FANIN_N) {
            g.concurrent(tio, sender, .{ tio, &q, @as(u64, i) }) catch {
                // No thread available: drain one value and retry.
                s +%= try q.getOne(tio);
                got += 1;
                continue;
            };
            spawned += 1;
            i += 1;
        }
        while (got < FANIN_N) : (got += 1) s +%= try q.getOne(tio);
        try g.await(tio);
        std.mem.doNotOptimizeAway(s);
        emit("fanin_before_mt", now() - t0, FANIN_N);
    }
    if (all or std.mem.eql(u8, which, "skew")) {
        const t0 = now();
        var g: Io.Group = .init;
        for (0..SKEW_N) |i| g.async(tio, work, .{i});
        try g.await(tio);
        emit("skew_before_mt", now() - t0, SKEW_N);
    }
}
