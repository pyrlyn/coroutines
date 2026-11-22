const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const coro = b.createModule(.{ .root_source_file = b.path("../../../src/root.zig"), .target = target, .optimize = .ReleaseFast });
    const m = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = .ReleaseFast, .link_libc = true });
    m.addImport("coroutines", coro);
    const exe = b.addExecutable(.{ .name = "bench-before", .root_module = m });
    b.installArtifact(exe);
}
