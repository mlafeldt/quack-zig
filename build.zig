const std = @import("std");

const DuckDBVersion = enum {
    @"1.0.0",
    @"1.1.0",
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",

    const default: DuckDBVersion = .@"1.1.3";
};

const Platform = enum {
    linux_amd64,
    linux_arm64,
    osx_amd64,
    osx_arm64,
    windows_amd64,
    windows_arm64,
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_version = b.option(DuckDBVersion, "duckdb-version", b.fmt("DuckDB version to build for (default: {s})", .{@tagName(DuckDBVersion.default)})) orelse DuckDBVersion.default;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse std.enums.values(Platform);
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;

    const ext_version = v: {
        const git_describe = b.run(&[_][]const u8{
            "git",
            "-C",
            b.build_root.path orelse ".",
            "describe",
            "--tags",
            "--match",
            "v[0-9]*",
            "--always",
        });
        break :v std.mem.trim(u8, git_describe, " \n\r");
    };

    const metadata_script = b.dependency("extension_ci_tools", .{})
        .path("scripts/append_extension_metadata.py")
        .getPath(b);

    for (platforms) |platform| {
        const target = b.resolveTargetQuery(switch (platform) {
            .linux_amd64 => .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu },
            .linux_arm64 => .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu },
            .osx_amd64 => .{ .os_tag = .macos, .cpu_arch = .x86_64, .abi = .none },
            .osx_arm64 => .{ .os_tag = .macos, .cpu_arch = .aarch64, .abi = .none },
            .windows_amd64 => .{ .os_tag = .windows, .cpu_arch = .x86_64, .abi = .gnu },
            .windows_arm64 => .{ .os_tag = .windows, .cpu_arch = .aarch64, .abi = .gnu },
        });

        const duckdb = b.lazyDependency(b.fmt("duckdb-{s}", .{@tagName(duckdb_version)}), .{}) orelse continue;

        const ext = b.addSharedLibrary(.{
            .name = "quack",
            .target = target,
            .optimize = optimize,
        });
        ext.addCSourceFiles(.{
            .files = &.{"quack_extension.c"},
            .flags = &cflags,
        });
        ext.addIncludePath(duckdb.path(""));
        ext.linkLibC();
        ext.root_module.addCMacro("DUCKDB_EXTENSION_NAME", ext.name);
        ext.root_module.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");

        const filename = b.fmt("{s}.duckdb_extension", .{ext.name});
        ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

        // TODO: Rewrite the metadata script in Zig
        const output = out: {
            const cmd = b.addSystemCommand(&.{ "python3", metadata_script });
            cmd.addArgs(&.{ "--extension-name", ext.name });
            cmd.addArgs(&.{ "--extension-version", ext_version });
            cmd.addArgs(&.{ "--duckdb-platform", @tagName(platform) });
            cmd.addArgs(&.{ "--duckdb-version", "v0.0.1" }); // TODO: Set this based on the DuckDB version
            cmd.addArg("--library-file");
            cmd.addArtifactArg(ext);
            cmd.addArg("--out-file");
            break :out cmd.addOutputFileArg(filename);
        };

        const install_dir = @tagName(platform);

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            output,
            .{ .custom = install_dir },
            filename,
        ).step);

        if (install_headers) {
            b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                .source_dir = duckdb.path(""),
                .include_extensions = &.{"h"},
                .install_dir = .header,
                .install_subdir = "",
            }).step);
        }
    }
}

const cflags = [_][]const u8{ "-Wall", "-Wextra", "-Werror" };
