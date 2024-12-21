const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{ .name = "zoap", .root_source_file = b.path("src/zoap.zig"), .optimize = optimize, .target = target });
    b.installArtifact(lib);

    var zoap_tests = b.addTest(.{ .root_source_file = b.path("src/zoap.zig"), .target = target, .optimize = optimize });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&zoap_tests.step);
}
