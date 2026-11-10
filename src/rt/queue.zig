//! Per-worker run queue: a fixed ring of 256 task pointers with one owner and
//! many thieves (the layout tokio uses). The owner pushes at the tail and pops
//! at the head (FIFO, so a yielding task really goes last); thieves claim half
//! of the queue from the head with one CAS, copy it, then release the claim.
//! When the ring is full, the owner moves half of it to the shared injector.
//!
//! `head` packs two u32 indices: `steal` (start of a claim in progress) and
//! `real` (next slot the owner pops). `steal == real` means no thief is active.
//! The owner never overwrites a slot in `[steal, tail)`.
//!
//! The owner keeps a private tail and publishes it (`publish`) in batches,
//! and checks room against a cached `steal`: a spawn loop then touches no
//! cache line that thieves write or read. Unpublished tasks are invisible to
//! thieves until the owner publishes (the runtime does so after every poll).
const std = @import("std");

pub const capacity: u32 = 256;
const mask: u32 = capacity - 1;

/// What the queue needs from an element: an intrusive `next` link, used only
/// to hand an overflow batch to the injector.
pub fn LocalQueue(comptime Node: type) type {
    return struct {
        const Self = @This();

        head: std.atomic.Value(u64) align(std.atomic.cache_line) = .init(0),
        /// Published tail (what thieves see).
        tail: std.atomic.Value(u32) align(std.atomic.cache_line) = .init(0),
        /// Owner-only: real tail and a lower bound of `steal`.
        ptail: u32 align(std.atomic.cache_line) = 0,
        cached_steal: u32 = 0,
        buf: [capacity]std.atomic.Value(?*Node) align(std.atomic.cache_line) = @splat(.init(null)),

        inline fn pack(steal: u32, real: u32) u64 {
            return (@as(u64, steal) << 32) | real;
        }
        inline fn stealOf(h: u64) u32 {
            return @truncate(h >> 32);
        }
        inline fn realOf(h: u64) u32 {
            return @truncate(h);
        }

        /// Published tasks in the ring, as other threads see it (approximate).
        pub fn len(q: *const Self) u32 {
            const h = q.head.load(.seq_cst);
            const t = q.tail.load(.seq_cst);
            return t -% realOf(h);
        }

        /// Other threads: whether there is anything to steal.
        pub fn isEmpty(q: *const Self) bool {
            return q.len() == 0;
        }

        /// Owner only: all tasks, published or not.
        pub fn ownerLen(q: *const Self) u32 {
            return q.ptail -% realOf(q.head.load(.monotonic));
        }

        /// Owner only: tasks pushed since the last `publish`.
        pub fn unpublished(q: *const Self) u32 {
            return q.ptail -% q.tail.raw;
        }

        /// Owner only: makes every pushed task visible to thieves.
        pub fn publish(q: *Self) void {
            // seq_cst: pairs with the seq_cst loads of an idle worker
            // re-checking queues before it parks (no lost wake-up).
            if (q.tail.raw != q.ptail) q.tail.store(q.ptail, .seq_cst);
        }

        /// Owner only. Pushes `n` at the tail (unpublished); on overflow,
        /// calls `overflow(ctx, first, last, count)` with a linked batch (via
        /// `next`) of half the ring plus `n`.
        pub fn push(q: *Self, n: *Node, ctx: anytype, comptime overflow: fn (@TypeOf(ctx), *Node, *Node, usize) void) void {
            const t = q.ptail;
            if (t -% q.cached_steal < capacity) {
                @branchHint(.likely);
                q.buf[t & mask].store(n, .monotonic);
                q.ptail = t +% 1;
                return;
            }
            while (true) {
                const h = q.head.load(.acquire);
                const steal = stealOf(h);
                const real = realOf(h);
                q.cached_steal = steal;
                if (t -% steal < capacity) {
                    q.buf[t & mask].store(n, .monotonic);
                    q.ptail = t +% 1;
                    return;
                }
                q.publish();
                if (steal != real) {
                    // A thief is copying; it will free room soon. Do not wait.
                    n.next = null;
                    overflow(ctx, n, n, 1);
                    return;
                }
                const half = capacity / 2;
                if (q.head.cmpxchgStrong(h, pack(real +% half, real +% half), .release, .monotonic) != null) continue;
                q.cached_steal = real +% half;
                const first = q.buf[real & mask].load(.monotonic).?;
                var prev = first;
                var i: u32 = 1;
                while (i < half) : (i += 1) {
                    const cur = q.buf[(real +% i) & mask].load(.monotonic).?;
                    prev.next = cur;
                    prev = cur;
                }
                prev.next = n;
                n.next = null;
                overflow(ctx, first, n, half + 1);
                return;
            }
        }

        /// Owner only. Pops from the head (published or not).
        pub fn pop(q: *Self) ?*Node {
            var h = q.head.load(.acquire);
            while (true) {
                const steal = stealOf(h);
                const real = realOf(h);
                if (real == q.ptail) return null;
                const next_real = real +% 1;
                const nh = if (steal == real) pack(next_real, next_real) else pack(steal, next_real);
                if (q.head.cmpxchgWeak(h, nh, .acq_rel, .acquire)) |actual| {
                    h = actual;
                    continue;
                }
                return q.buf[real & mask].load(.monotonic);
            }
        }

        /// Called by the owner of `dst` on another worker's queue `src`.
        /// Moves half of `src` (rounded up) into `dst` and returns one of the
        /// stolen tasks to run right away, or null.
        pub fn stealInto(src: *Self, dst: *Self) ?*Node {
            const dst_tail = dst.ptail;
            const dst_steal = stealOf(dst.head.load(.acquire));
            dst.cached_steal = dst_steal;
            if (dst_tail -% dst_steal > capacity / 2) return null;

            var prev = src.head.load(.acquire);
            var n: u32 = undefined;
            var next: u64 = undefined;
            while (true) {
                const steal = stealOf(prev);
                const real = realOf(prev);
                if (steal != real) return null; // another thief is active
                const t = src.tail.load(.acquire);
                n = t -% real;
                n -= n / 2;
                if (n == 0) return null;
                if (n > capacity / 2) return null; // inconsistent snapshot
                next = pack(steal, real +% n);
                if (src.head.cmpxchgWeak(prev, next, .acq_rel, .acquire)) |actual| {
                    prev = actual;
                    continue;
                }
                break;
            }
            const first = stealOf(prev);
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const v = src.buf[(first +% i) & mask].load(.monotonic);
                dst.buf[(dst_tail +% i) & mask].store(v, .monotonic);
            }
            // Release the claim: steal catches up with real.
            prev = next;
            while (true) {
                const real = realOf(prev);
                if (src.head.cmpxchgWeak(prev, pack(real, real), .acq_rel, .acquire)) |actual| {
                    prev = actual;
                    continue;
                }
                break;
            }
            n -= 1;
            const ret = dst.buf[(dst_tail +% n) & mask].load(.monotonic);
            if (n > 0) {
                dst.ptail = dst_tail +% n;
                dst.publish();
            }
            return ret;
        }
    };
}

const testing = std.testing;
const TNode = struct { next: ?*TNode = null, id: usize = 0 };
const Sink = struct {
    got: usize = 0,
    fn overflow(s: *Sink, first: *TNode, last: *TNode, count: usize) void {
        var c: usize = 0;
        var it: ?*TNode = first;
        while (it) |n| : (it = n.next) c += 1;
        std.debug.assert(c == count);
        _ = last;
        s.got += count;
    }
};

test "LocalQueue is FIFO for the owner and overflows half" {
    var q: LocalQueue(TNode) = .{};
    var nodes: [capacity + 1]TNode = undefined;
    for (&nodes, 0..) |*n, i| n.* = .{ .id = i };
    var sink: Sink = .{};
    for (nodes[0..capacity]) |*n| q.push(n, &sink, Sink.overflow);
    try testing.expectEqual(@as(usize, 0), sink.got);
    try testing.expectEqual(capacity, q.ownerLen());
    try testing.expectEqual(@as(u32, 0), q.len());
    q.publish();
    try testing.expectEqual(capacity, q.len());
    q.push(&nodes[capacity], &sink, Sink.overflow);
    try testing.expectEqual(@as(usize, capacity / 2 + 1), sink.got);
    var expect: usize = capacity / 2;
    while (q.pop()) |n| : (expect += 1) try testing.expectEqual(expect, n.id);
    try testing.expectEqual(@as(usize, capacity), expect);
}

test "LocalQueue steal moves half and every task is seen once" {
    var a: LocalQueue(TNode) = .{};
    var b: LocalQueue(TNode) = .{};
    var nodes: [100]TNode = undefined;
    for (&nodes, 0..) |*n, i| n.* = .{ .id = i };
    var sink: Sink = .{};
    for (&nodes) |*n| a.push(n, &sink, Sink.overflow);
    try testing.expectEqual(@as(?*TNode, null), a.stealInto(&b)); // unpublished
    a.publish();
    const first = a.stealInto(&b).?;
    try testing.expectEqual(@as(u32, 49), b.len());
    try testing.expectEqual(@as(u32, 50), a.len());
    var seen: [100]bool = @splat(false);
    seen[first.id] = true;
    while (a.pop()) |n| seen[n.id] = true;
    while (b.pop()) |n| seen[n.id] = true;
    for (seen) |s| try testing.expect(s);
}

test "LocalQueue concurrent push/pop/steal loses nothing" {
    const N = 200_000;
    const Shared = struct {
        q: LocalQueue(TNode) = .{},
        done: std.atomic.Value(bool) = .init(false),
        count: std.atomic.Value(usize) = .init(0),
        overflowed: std.atomic.Value(usize) = .init(0),
        fn overflow(s: *@This(), first: *TNode, last: *TNode, c: usize) void {
            _ = first;
            _ = last;
            _ = s.overflowed.fetchAdd(c, .monotonic);
        }
        fn thief(s: *@This()) void {
            var mine: LocalQueue(TNode) = .{};
            while (!s.done.load(.acquire)) {
                if (s.q.stealInto(&mine)) |_| {
                    var c: usize = 1;
                    while (mine.pop()) |_| c += 1;
                    _ = s.count.fetchAdd(c, .monotonic);
                } else std.atomic.spinLoopHint();
            }
        }
    };
    const nodes = try testing.allocator.alloc(TNode, N);
    defer testing.allocator.free(nodes);
    var s: Shared = .{};
    var th: [3]std.Thread = undefined;
    for (&th) |*t| t.* = try std.Thread.spawn(.{}, Shared.thief, .{&s});
    var own: usize = 0;
    for (nodes, 0..) |*n, i| {
        n.* = .{ .id = i };
        s.q.push(n, &s, Shared.overflow);
        if (i % 5 == 0) s.q.publish();
        if (i % 3 == 0) {
            if (s.q.pop()) |_| own += 1;
        }
    }
    while (s.q.pop()) |_| own += 1;
    s.done.store(true, .release);
    for (th) |t| t.join();
    try testing.expectEqual(@as(usize, N), own + s.count.load(.monotonic) + s.overflowed.load(.monotonic));
}
