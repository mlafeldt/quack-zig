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

// TODO: Switch to Python package once it's available
const sqllogictest_repo = "git+https://github.com/duckdb/duckdb-sqllogictest-python@faf6f19";
const metadata_script = "https://raw.githubusercontent.com/duckdb/extension-ci-tools/refs/heads/v1.1.3/scripts/append_extension_metadata.py";

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_version = b.option(DuckDBVersion, "duckdb-version", b.fmt("DuckDB version to build for (default: {s})", .{@tagName(DuckDBVersion.default)})) orelse DuckDBVersion.default;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse std.enums.values(Platform);
    // HACK: Allow to override platform for GitHub Actions where linux_amd64_gcc4 is used
    const platform_suffix = b.option([]const u8, "platform-suffix", "Add suffix to platform name, e.g. gcc4");
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

    for (platforms) |platform| {
        const target = b.resolveTargetQuery(switch (platform) {
            .linux_amd64 => .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu },
            .linux_arm64 => .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu },
            .osx_amd64 => .{ .os_tag = .macos, .cpu_arch = .x86_64, .abi = .none },
            .osx_arm64 => .{ .os_tag = .macos, .cpu_arch = .aarch64, .abi = .none },
            .windows_amd64 => .{ .os_tag = .windows, .cpu_arch = .x86_64, .abi = .gnu },
            .windows_arm64 => .{ .os_tag = .windows, .cpu_arch = .aarch64, .abi = .gnu },
        });
        const platform_name = if (platform_suffix) |suffix| b.fmt("{s}_{s}", .{ @tagName(platform), suffix }) else @tagName(platform);

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
        const ext_path = out: {
            const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3", metadata_script });
            cmd.addArgs(&.{ "--extension-name", ext.name });
            cmd.addArgs(&.{ "--extension-version", ext_version });
            cmd.addArgs(&.{ "--duckdb-platform", platform_name });
            cmd.addArgs(&.{ "--duckdb-version", "v0.0.1" }); // TODO: Set this based on the DuckDB version
            cmd.addArg("--library-file");
            cmd.addArtifactArg(ext);
            cmd.addArg("--out-file");
            break :out cmd.addOutputFileArg(filename);
        };

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            ext_path,
            .{ .custom = platform_name },
            filename,
        ).step);

        if (install_headers) {
            const header_dirs = [_]std.Build.LazyPath{
                duckdb.path(""),
                // Add more header directories here
            };
            for (header_dirs) |dir| {
                b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                    .source_dir = dir,
                    .include_extensions = &.{"h"},
                    .install_dir = .header,
                    .install_subdir = "",
                }).step);
            }
        }

        // Run tests on native platform
        if (b.host.result.os.tag == target.result.os.tag and b.host.result.cpu.arch == target.result.cpu.arch) {
            const cmd = b.addSystemCommand(&.{ "uv", "run" });
            cmd.addArg("--quiet");
            cmd.addArgs(&.{ "--with", sqllogictest_repo });
            cmd.addArgs(&.{ "--with", b.fmt("duckdb=={s}", .{@tagName(duckdb_version)}) });
            cmd.addArgs(&.{ "python3", "-m", "duckdb_sqllogictest" });
            cmd.addArgs(&.{ "--test-dir", "test" });
            cmd.addArg("--external-extension");
            cmd.addFileArg(ext_path);

            const test_step = b.step("test", "Run unit tests with sqllogictest");
            test_step.dependOn(&cmd.step);
        }
    }
}

const cflags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-Werror",
    "-fvisibility=hidden", // Avoid symbol clashes
};
