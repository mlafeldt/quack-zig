const std = @import("std");

const Platform = enum {
    linux_amd64,
    linux_arm64,
    osx_amd64,
    osx_arm64,
    windows_amd64,
    windows_arm64,
};

pub fn build(b: *std.Build) !void {
    const platform = b.option(Platform, "duckdb-platform", "DuckDB platform to build for") orelse Platform.osx_arm64;
    const platform_name = @tagName(platform);

    const target = b.resolveTargetQuery(switch (platform) {
        .linux_amd64 => .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu },
        .linux_arm64 => .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu },
        .osx_amd64 => .{ .os_tag = .macos, .cpu_arch = .x86_64, .abi = .none },
        .osx_arm64 => .{ .os_tag = .macos, .cpu_arch = .aarch64, .abi = .none },
        .windows_amd64 => .{ .os_tag = .windows, .cpu_arch = .x86_64, .abi = .gnu },
        .windows_arm64 => .{ .os_tag = .windows, .cpu_arch = .aarch64, .abi = .gnu },
    });
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("duckdb", .{});
    const duckdb = b.addStaticLibrary(.{
        .name = "duckdb",
        .target = target,
        .optimize = optimize,
    });
    duckdb.addCSourceFiles(.{
        .files = &.{"duckdb.cpp"},
        .root = upstream.path(""),
        .flags = &.{
            // Fix error: expansion of date or time macro is not reproducible
            // https://github.com/duckdb/duckdb/blob/v1.1.3/third_party/pcg/pcg_extras.hpp#L628
            "-Wno-date-time",
        },
    });
    duckdb.installHeadersDirectory(upstream.path("."), "", .{});
    duckdb.linkLibCpp();
    duckdb.root_module.addCMacro("DUCKDB_STATIC_BUILD", "1");

    const ext = b.addSharedLibrary(.{
        .name = "quack",
        .target = target,
        .optimize = optimize,
    });
    ext.addCSourceFiles(.{
        .files = &.{"quack.c"},
        .flags = &cflags,
    });
    ext.linkLibrary(duckdb);
    ext.linkLibC();
    ext.root_module.addCMacro("DUCKDB_EXTENSION_NAME", ext.name);
    ext.root_module.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");

    const filename = b.fmt("{s}.duckdb_extension", .{ext.name});
    ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

    const output = out: {
        const tools = b.dependency("extension_ci_tools", .{});
        const cmd = b.addSystemCommand(&.{
            "python3",
            tools.path("scripts/append_extension_metadata.py").getPath(b),
        });
        cmd.addArgs(&.{ "--extension-name", ext.name });
        cmd.addArgs(&.{ "--extension-version", "v0.0.0" });
        cmd.addArgs(&.{ "--duckdb-version", "v0.0.1" });
        cmd.addArgs(&.{ "--duckdb-platform", platform_name });
        cmd.addArg("--library-file");
        cmd.addArtifactArg(ext);
        cmd.addArg("--out-file");
        break :out cmd.addOutputFileArg(filename);
    };

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(
        output,
        .{ .custom = platform_name },
        filename,
    ).step);

    b.getInstallStep().dependOn(&b.addInstallArtifact(duckdb, .{
        .dest_dir = .{ .override = .{ .custom = platform_name } },
    }).step);
}

const cflags = [_][]const u8{ "-Wall", "-Wextra", "-Werror" };
