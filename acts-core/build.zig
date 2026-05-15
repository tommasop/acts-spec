const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "Build version") orelse "dev";
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "acts",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(b.path("vendor"));
    exe.addCSourceFile(.{
        .file = b.path("vendor/sqlite3.c"),
        .flags = &.{
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
        },
    });
    exe.root_module.addOptions("build_options", options);

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
    exe_unit_tests.addIncludePath(b.path("vendor"));
    exe_unit_tests.addCSourceFile(.{
        .file = b.path("vendor/sqlite3.c"),
        .flags = &.{
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
        },
    });
    exe_unit_tests.root_module.addOptions("build_options", options);

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
    release_exe.addIncludePath(b.path("vendor"));
    release_exe.addCSourceFile(.{
        .file = b.path("vendor/sqlite3.c"),
        .flags = &.{
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
        },
    });
    release_exe.root_module.addOptions("build_options", options);

    const install_release = b.addInstallArtifact(release_exe, .{});
    release_step.dependOn(&install_release.step);

    // Cross-compilation targets
    const cross_step = b.step("cross", "Cross-compile for all targets");
    
    const targets = [_]std.Target.Query{
        std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux-gnu" }) catch unreachable,
        std.Target.Query.parse(.{ .arch_os_abi = "aarch64-linux-gnu" }) catch unreachable,
        std.Target.Query.parse(.{ .arch_os_abi = "x86_64-macos-none" }) catch unreachable,
        std.Target.Query.parse(.{ .arch_os_abi = "aarch64-macos-none" }) catch unreachable,
    };
    
    const target_names = [_][]const u8{
        "linux-x86_64",
        "linux-aarch64",
        "macos-x86_64",
        "macos-aarch64",
    };

    for (targets, target_names) |t, name| {
        const cross_exe = b.addExecutable(.{
            .name = b.fmt("acts-{s}", .{name}),
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });
        cross_exe.linkLibC();
        cross_exe.addIncludePath(b.path("vendor"));
        cross_exe.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = &.{
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_ENABLE_FTS5",
                "-DSQLITE_ENABLE_JSON1",
            },
        });
        cross_exe.root_module.addOptions("build_options", options);

        const install_cross = b.addInstallArtifact(cross_exe, .{});
        cross_step.dependOn(&install_cross.step);
    }
}
