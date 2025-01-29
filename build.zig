const std = @import("std");
const Build = std.Build;

const DuckDBVersion = enum {
    @"1.1.0", // First version with C API support
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",
    @"1.2.0",

    const all = std.enums.values(DuckDBVersion);

    fn string(self: DuckDBVersion, b: *Build) []const u8 {
        return b.fmt("v{s}", .{@tagName(self)});
    }

    fn headers(self: DuckDBVersion, b: *Build) ?Build.LazyPath {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => if (b.lazyDependency("libduckdb_1_1_3", .{})) |dep| dep.path("") else null,
            .@"1.2.0" => if (b.lazyDependency("libduckdb_headers", .{})) |dep| dep.path("1.2.0") else null,
        };
    }

    fn extensionAPIVersion(self: DuckDBVersion) [:0]const u8 {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => "v0.0.1",
            .@"1.2.0" => "v1.2.0",
        };
    }
};

const Platform = enum {
    linux_amd64, // Node.js packages, etc.
    linux_amd64_gcc4, // Python packages, CLI, etc.
    linux_arm64,
    linux_arm64_gcc4,
    osx_amd64,
    osx_arm64,
    windows_amd64,
    windows_arm64,

    const all = std.enums.values(Platform);

    fn string(self: Platform) [:0]const u8 {
        return @tagName(self);
    }

    fn target(self: Platform, b: *Build) Build.ResolvedTarget {
        return b.resolveTargetQuery(switch (self) {
            .linux_amd64 => .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu },
            .linux_amd64_gcc4 => .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu }, // TODO: Set glibc_version?
            .linux_arm64 => .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu },
            .linux_arm64_gcc4 => .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu }, // TODO: Set glibc_version?
            .osx_amd64 => .{ .os_tag = .macos, .cpu_arch = .x86_64, .abi = .none },
            .osx_arm64 => .{ .os_tag = .macos, .cpu_arch = .aarch64, .abi = .none },
            .windows_amd64 => .{ .os_tag = .windows, .cpu_arch = .x86_64, .abi = .gnu },
            .windows_arm64 => .{ .os_tag = .windows, .cpu_arch = .aarch64, .abi = .gnu },
        });
    }
};

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_versions = b.option([]const DuckDBVersion, "duckdb-version", "DuckDB version(s) to build for (default: all)") orelse DuckDBVersion.all;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse Platform.all;
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;

    const test_step = b.step("test", "Run SQL logic tests");

    const ext_version = v: {
        var code: u8 = undefined;
        const git_describe = b.runAllowFail(&[_][]const u8{
            "git",
            "-C",
            b.build_root.path orelse ".",
            "describe",
            "--tags",
            "--match",
            "v[0-9]*",
            "--always",
        }, &code, .Ignore) catch "n/a";
        break :v std.mem.trim(u8, git_describe, " \n\r");
    };

    const metadata_script = b.dependency("extension_ci_tools", .{}).path("scripts/append_extension_metadata.py");

    for (duckdb_versions) |duckdb_version| {
        const version_string = duckdb_version.string(b);
        const duckdb_headers = duckdb_version.headers(b) orelse continue;

        for (platforms) |platform| {
            const platform_string = platform.string();
            const target = platform.target(b);

            const ext = b.addSharedLibrary(.{
                .name = "quack",
                .target = target,
                .optimize = optimize,
            });
            ext.addCSourceFiles(.{
                .files = &.{
                    "quack_extension.c",
                },
                .root = b.path("src"),
                .flags = &cflags,
            });
            ext.addIncludePath(duckdb_headers);
            ext.linkLibC();
            ext.root_module.addCMacro("DUCKDB_EXTENSION_NAME", ext.name);
            ext.root_module.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");

            const filename = b.fmt("{s}.duckdb_extension", .{ext.name});
            ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

            const ext_path = path: {
                const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12" });
                cmd.addFileArg(metadata_script);
                cmd.addArgs(&.{ "--extension-name", ext.name });
                cmd.addArgs(&.{ "--extension-version", ext_version });
                cmd.addArgs(&.{ "--duckdb-platform", platform_string });
                cmd.addArgs(&.{ "--duckdb-version", duckdb_version.extensionAPIVersion() });
                cmd.addArg("--library-file");
                cmd.addArtifactArg(ext);
                cmd.addArg("--out-file");
                const path = cmd.addOutputFileArg(filename);

                cmd.step.name = b.fmt("metadata {s} {s}", .{ version_string, platform_string });
                break :path path;
            };

            const install_file = b.addInstallFileWithDir(ext_path, .{
                .custom = b.fmt("{s}/{s}", .{ version_string, platform_string }),
            }, filename);
            install_file.step.name = b.fmt("install {s} {s}", .{ version_string, platform_string });
            b.getInstallStep().dependOn(&install_file.step);

            if (install_headers) {
                const header_dirs = [_]Build.LazyPath{
                    duckdb_headers,
                    // Add more header directories here
                };
                for (header_dirs) |dir| {
                    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                        .source_dir = dir,
                        .include_extensions = &.{"h"},
                        .install_dir = .{ .custom = version_string },
                        .install_subdir = "include",
                    }).step);
                }
            }

            // Run tests on native platform
            if (b.host.result.os.tag == target.result.os.tag and
                b.host.result.cpu.arch == target.result.cpu.arch and
                duckdb_version != .@"1.2.0") // TODO: Remove once Python package is available
            {
                const sqllogictest = b.lazyDependency("sqllogictest", .{}) orelse continue;

                const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12", "--with" });
                cmd.addFileArg(sqllogictest.path(""));
                cmd.addArgs(&.{ "--with", b.fmt("duckdb=={s}", .{@tagName(duckdb_version)}) });
                cmd.addArgs(&.{ "python3", "-m", "duckdb_sqllogictest" });
                cmd.addArgs(&.{ "--test-dir", "test" });
                cmd.addArg("--external-extension");
                cmd.addFileArg(ext_path);
                cmd.step.name = b.fmt("sqllogictest {s} {s}", .{ version_string, platform_string });

                test_step.dependOn(&cmd.step);
            }
        }
    }
}

const cflags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-Werror",
    "-fvisibility=hidden", // Avoid symbol clashes
};
