const std = @import("std");
const Build = std.Build;

pub const Version = enum {
    @"1.1.0", // First version with C API support
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",
    @"1.2.0",

    pub const all = std.enums.values(@This());

    pub fn string(self: @This(), b: *Build) []const u8 {
        return b.fmt("v{s}", .{@tagName(self)});
    }

    pub fn headers(self: @This(), b: *Build) Build.LazyPath {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => b.dependency("libduckdb_1_1_3", .{}).path(""),
            .@"1.2.0" => b.dependency("libduckdb_headers", .{}).path("1.2.0"),
        };
    }

    pub fn extensionAPIVersion(self: @This()) [:0]const u8 {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => "v0.0.1",
            .@"1.2.0" => "v1.2.0",
        };
    }
};

pub const Platform = enum {
    linux_amd64, // Node.js packages, etc.
    linux_amd64_gcc4, // Python packages, CLI, etc.
    linux_arm64,
    linux_arm64_gcc4,
    osx_amd64,
    osx_arm64,
    windows_amd64,
    windows_arm64,

    pub const all = std.enums.values(@This());

    pub fn string(self: @This()) [:0]const u8 {
        return @tagName(self);
    }

    pub fn target(self: @This(), b: *Build) Build.ResolvedTarget {
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

pub const Options = struct {
    ext_name: []const u8,
    optimize: std.builtin.OptimizeMode = .Debug,
    duckdb_versions: []const Version = Version.all,
    platforms: []const Platform = Platform.all,
    install_headers: bool = false,
    flat: bool = false,
};

pub fn buildExtension(b: *Build, opts: Options) !void {
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
    const sqllogictest = b.dependency("sqllogictest", .{}).path("");

    for (opts.duckdb_versions) |duckdb_version| {
        const version_string = duckdb_version.string(b);
        const duckdb_headers = duckdb_version.headers(b);

        for (opts.platforms) |platform| {
            const platform_string = platform.string();
            const target = platform.target(b);

            const ext = b.addSharedLibrary(.{
                .name = opts.ext_name,
                .target = target,
                .optimize = opts.optimize,
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
            ext.root_module.addCMacro("DUCKDB_EXTENSION_NAME", opts.ext_name);
            ext.root_module.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");

            const filename = b.fmt("{s}.duckdb_extension", .{opts.ext_name});
            ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

            const ext_path = path: {
                const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12" });
                cmd.addFileArg(metadata_script);
                cmd.addArgs(&.{ "--extension-name", opts.ext_name });
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
                .custom = if (opts.flat) platform_string else b.fmt("{s}/{s}", .{ version_string, platform_string }),
            }, filename);
            install_file.step.name = b.fmt("install {s} {s}", .{ version_string, platform_string });
            b.getInstallStep().dependOn(&install_file.step);

            if (opts.install_headers) {
                const header_dirs = [_]Build.LazyPath{
                    duckdb_headers,
                    // Add more header directories here
                };
                for (header_dirs) |dir| {
                    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                        .source_dir = dir,
                        .include_extensions = &.{"h"},
                        .install_dir = if (opts.flat) .header else .{ .custom = b.fmt("{s}/include", .{version_string}) },
                        .install_subdir = "",
                    }).step);
                }
            }

            // Run tests on native platform
            if (b.graph.host.result.os.tag == target.result.os.tag and
                b.graph.host.result.cpu.arch == target.result.cpu.arch and
                duckdb_version != .@"1.2.0") // TODO: Remove once Python package is available
            {
                const cmd = b.addSystemCommand(&.{ "uv", "run", "--python=3.12", "--with" });
                cmd.addFileArg(sqllogictest);
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
