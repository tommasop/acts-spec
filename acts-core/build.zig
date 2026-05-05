const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "acts",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link SQLite3
    // Note: For cross-compilation, sqlite3 must be vendored as sqlite3.c
    // and compiled inline. This is planned for v1.1.
    // For v1.0.0, native compilation requires system sqlite3-dev package.
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.linkLibC();
    exe_unit_tests.linkSystemLibrary("sqlite3");

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Release build for current target
    const release_step = b.step("release", "Build optimized release binary for current target");
    const release_exe = b.addExecutable(.{
        .name = "acts",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    release_exe.linkLibC();
    release_exe.linkSystemLibrary("sqlite3");

    const install_release = b.addInstallArtifact(release_exe, .{});
    release_step.dependOn(&install_release.step);
}
