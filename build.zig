const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("coroutines", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // Hybrid backend end-to-end (processes mode re-executes this binary).
    const e2e_mod = b.createModule(.{
        .root_source_file = b.path("tests/hybrid_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_mod.addImport("coroutines", mod);
    const e2e = b.addExecutable(.{ .name = "hybrid-e2e", .root_module = e2e_mod });
    test_step.dependOn(&b.addRunArtifact(e2e).step);

    // Benchmarks are always ReleaseFast.
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = target.result.os.tag != .windows,
    });
    bench_mod.addImport("coroutines", b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    }));
    const bench_exe = b.addExecutable(.{ .name = "bench", .root_module = bench_mod });
    b.installArtifact(bench_exe);
    const run_bench = b.addRunArtifact(bench_exe);
    b.step("bench", "Run benchmarks (ReleaseFast)").dependOn(&run_bench.step);
}
