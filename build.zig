const std = @import("std");
const Build = std.Build;

const DuckDBVersion = enum {
    @"1.0.0",
    @"1.1.0",
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",

    const latest: DuckDBVersion = .@"1.1.3";
};

const Platform = enum {
    linux_amd64,
    linux_amd64_gcc4,
    linux_arm64,
    linux_arm64_gcc4,
    osx_amd64,
    osx_arm64,
    windows_amd64,
    windows_arm64,

    const all = std.enums.values(Platform);

    fn name(self: Platform) [:0]const u8 {
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
    const duckdb_version = b.option(DuckDBVersion, "duckdb-version", b.fmt("DuckDB version to build for (default: {s})", .{@tagName(DuckDBVersion.latest)})) orelse DuckDBVersion.latest;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse Platform.all;
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;

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

    for (platforms) |platform| {
        const target = platform.target(b);
        const duckdb = b.lazyDependency(b.fmt("duckdb-{s}", .{@tagName(duckdb_version)}), .{}) orelse continue;

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
        ext.addIncludePath(duckdb.path(""));
        ext.linkLibC();
        ext.root_module.addCMacro("DUCKDB_EXTENSION_NAME", ext.name);
        ext.root_module.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");

        const filename = b.fmt("{s}.duckdb_extension", .{ext.name});
        ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

        const ext_path = path: {
            const metadata_script = b.dependency("extension_ci_tools", .{}).path("scripts/append_extension_metadata.py");

            const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12" });
            cmd.addFileArg(metadata_script);
            cmd.addArgs(&.{ "--extension-name", ext.name });
            cmd.addArgs(&.{ "--extension-version", ext_version });
            cmd.addArgs(&.{ "--duckdb-platform", platform.name() });
            cmd.addArgs(&.{ "--duckdb-version", "v0.0.1" }); // TODO: Set this based on the DuckDB version
            cmd.addArg("--library-file");
            cmd.addArtifactArg(ext);
            cmd.addArg("--out-file");
            const path = cmd.addOutputFileArg(filename);

            cmd.step.name = b.fmt("add metadata {s}", .{platform.name()});
            break :path path;
        };

        const install_file = b.addInstallFileWithDir(ext_path, .{ .custom = platform.name() }, filename);
        install_file.step.name = b.fmt("install {s}/{s}", .{ platform.name(), filename });
        b.getInstallStep().dependOn(&install_file.step);

        if (install_headers) {
            const header_dirs = [_]Build.LazyPath{
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
            const sqllogictest = b.lazyDependency("sqllogictest", .{}) orelse continue;

            const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12", "--with" });
            cmd.addFileArg(sqllogictest.path(""));
            cmd.addArgs(&.{ "--with", b.fmt("duckdb=={s}", .{@tagName(duckdb_version)}) });
            cmd.addArgs(&.{ "python3", "-m", "duckdb_sqllogictest" });
            cmd.addArgs(&.{ "--test-dir", "test" });
            cmd.addArg("--external-extension");
            cmd.addFileArg(ext_path);
            cmd.step.name = "sqllogictest";

            const test_step = b.step("test", "Run SQL logic tests");
            test_step.dependOn(&cmd.step);
            break;
        }
    }
}

const cflags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-Werror",
    "-fvisibility=hidden", // Avoid symbol clashes
};
