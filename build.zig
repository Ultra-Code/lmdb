const std = @import("std");
const mem = std.mem;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    const lmdb_upstream = b.dependency(
        "lmdb",
        .{ .target = target, .optimize = optimize },
    );
    const lmdb_root = "libraries/liblmdb";

    const strip = b.option(bool, "strip", "Strip debug information") orelse false;
    const lto = b.option(bool, "lto", "Enable link time optimization") orelse false;

    const liblmdb = b.addStaticLibrary(.{
        .name = "lmdb",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
        .use_llvm = switch (optimize) {
            .Debug => false,
            else => true,
        },
        .use_lld = switch (optimize) {
            .Debug => false,
            else => true,
        },
    });
    liblmdb.want_lto = lto;

    const liblmdb_src = .{
        "mdb.c",
        "midl.c",
    };
    const lmdb_includes = .{
        "lmdb.h",
        "midl.h",
    };
    const cflags = .{
        "-pthread",
        "-std=c23",
    };

    liblmdb.addCSourceFiles(.{
        .root = lmdb_upstream.path(lmdb_root),
        .files = &liblmdb_src,
        .flags = &cflags,
    });
    liblmdb.addIncludePath(lmdb_upstream.path(lmdb_root));
    liblmdb.root_module.addCMacro("_XOPEN_SOURCE", "600");

    liblmdb.installHeadersDirectory(
        lmdb_upstream.path(lmdb_root),
        "",
        .{ .include_extensions = &lmdb_includes },
    );

    b.installArtifact(liblmdb);

    const lmdb_tools = [_][]const u8{
        "mdb_copy.c",
        "mdb_drop.c",
        "mdb_dump.c",
        "mdb_load.c",
        "mdb_stat.c",
        "mplay.c",
    };

    const tools_step = b.step("tools", "Install lmdb tools");

    for (lmdb_tools) |tool_file| {
        const bin_name = tool_file[0..mem.indexOfScalar(u8, tool_file, '.').?];
        const tool = b.addExecutable(.{
            .name = bin_name,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .strip = strip,
            .use_llvm = switch (optimize) {
                .Debug => false,
                else => true,
            },
            .use_lld = switch (optimize) {
                .Debug => false,
                else => true,
            },
        });
        tool.addCSourceFiles(.{
            .root = lmdb_upstream.path(lmdb_root),
            .files = &.{tool_file},
            .flags = &cflags,
        });
        tool.addIncludePath(lmdb_upstream.path(lmdb_root));
        tool.root_module.addCMacro("_XOPEN_SOURCE", "600");
        tool.linkLibrary(liblmdb);

        const install_tool = b.addInstallArtifact(tool, .{});
        tools_step.dependOn(&install_tool.step);
    }

    const lmdb_api = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const absolute_include = b.pathJoin(&.{
        lmdb_upstream.path(lmdb_root).getPath3(b, null).root_dir.path.?,
        lmdb_upstream.path(lmdb_root).getPath3(b, null).sub_path,
    });
    // TODO: update when https://github.com/ziglang/zig/pull/20851 is available
    lmdb_api.addIncludeDir(absolute_include);

    _ = b.addModule("lmdb", .{
        .root_source_file = lmdb_api.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const cflags_test = .{
        "-pthread",
        "-std=c17", //c23 forbids function use without prototype
        "-Wno-format",
        "-Wno-implicit-function-declaration",
    };

    const lmdb_test = [_][]const u8{
        "mtest.c",
        "mtest2.c",
        "mtest3.c",
        "mtest4.c",
        "mtest5.c",
        "mtest6.c",
    };

    const test_step = b.step("test", "Run lmdb unit tests");

    for (lmdb_test) |test_file| {
        const test_name = test_file[0..mem.indexOfScalar(u8, test_file, '.').?];
        const test_exe = b.addExecutable(.{
            .name = test_name,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_exe.addCSourceFiles(.{
            .root = lmdb_upstream.path(lmdb_root),
            .files = &.{test_file},
            .flags = &cflags_test,
        });
        test_exe.addIncludePath(lmdb_upstream.path(lmdb_root));
        test_exe.linkLibrary(liblmdb);

        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }
}
