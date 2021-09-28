const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("zoap", "src/zoap.zig");
    lib.setBuildMode(mode);
    lib.install();

    var zoap_tests = b.addTest("src/zoap.zig");
    zoap_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&zoap_tests.step);
}
