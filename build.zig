const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_versions = b.option([]const DuckDBVersion, "duckdb-version", "DuckDB version(s) to build for (default: all)") orelse DuckDBVersion.all;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse Platform.all;
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;
    const flat = b.option(bool, "flat", "Install files without DuckDB version prefix") orelse false;
    const ExtensionLanguage = enum { c, zig };
    const lang = b.option(ExtensionLanguage, "lang", "Language to build the extension in (default: c)") orelse .c;

    if (flat and duckdb_versions.len > 1) {
        std.zig.fatal("-Dflat requires passing a specific DuckDB version", .{});
    }

    const test_step = b.step("test", "Run SQL logic tests");
    const check_step = b.step("check", "Check if extension compiles");

    const metadata_script = b.dependency("extension_ci_tools", .{}).path("scripts/append_extension_metadata.py");
    const sqllogictest = b.dependency("sqllogictest", .{}).path("");

    const ext_version = detectGitVersion(b) catch "n/a";

    for (duckdb_versions) |duckdb_version| {
        const version_string = duckdb_version.toString(b);
        const duckdb_headers = duckdb_version.headers(b);

        for (platforms) |platform| {
            const platform_string = platform.toString();
            const target = platform.target(b);

            const ext_name = "quack";
            const ext_mod = b.createModule(.{
                .link_libc = true,
                .root_source_file = switch (lang) {
                    .c => null,
                    .zig => b.path("src/quack_extension.zig"),
                },
                .target = target,
                .optimize = optimize,
            });
            ext_mod.addCSourceFiles(.{
                .files = &.{switch (lang) {
                    .c => "quack_extension.c",
                    .zig => "quack_extension_zig_wrapper.c",
                }},
                .root = b.path("src"),
                .flags = &cflags,
            });
            ext_mod.addIncludePath(duckdb_headers);
            ext_mod.addCMacro("DUCKDB_EXTENSION_NAME", ext_name);
            ext_mod.addCMacro("DUCKDB_BUILD_LOADABLE_EXTENSION", "1");
            const ext = b.addSharedLibrary(.{ .name = ext_name, .root_module = ext_mod });

            const filename = b.fmt("{s}.duckdb_extension", .{ext_name});
            ext.install_name = b.fmt("@rpath/{s}", .{filename}); // macOS only

            const ext_path = path: {
                const cmd = Build.Step.Run.create(b, b.fmt("metadata {s} {s}", .{ version_string, platform_string }));
                cmd.addArgs(&.{ "uv", "run", "--python=3.12" });
                cmd.addFileArg(metadata_script);
                cmd.addArgs(&.{ "--extension-name", ext_name });
                cmd.addArgs(&.{ "--extension-version", ext_version });
                cmd.addArgs(&.{ "--duckdb-platform", platform_string });
                cmd.addArgs(&.{ "--duckdb-version", duckdb_version.extensionAPIVersion() });
                cmd.addArg("--library-file");
                cmd.addArtifactArg(ext);
                cmd.addArg("--out-file");
                break :path cmd.addOutputFileArg(filename);
            };

            {
                const install_file = b.addInstallFileWithDir(ext_path, .{
                    .custom = if (flat) platform_string else b.fmt("{s}/{s}", .{ version_string, platform_string }),
                }, filename);
                install_file.step.name = b.fmt("install {s} {s}", .{ version_string, platform_string });
                b.getInstallStep().dependOn(&install_file.step);
            }

            if (install_headers) {
                const header_dirs = [_]Build.LazyPath{
                    duckdb_headers,
                    // Add more header directories here
                };
                for (header_dirs) |dir| {
                    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                        .source_dir = dir,
                        .include_extensions = &.{"h"},
                        .install_dir = if (flat) .header else .{ .custom = b.fmt("{s}/include", .{version_string}) },
                        .install_subdir = "",
                    }).step);
                }
            }

            // Run tests on native platform
            if (b.graph.host.result.os.tag == target.result.os.tag and
                b.graph.host.result.cpu.arch == target.result.cpu.arch)
            {
                const cmd = Build.Step.Run.create(b, b.fmt("sqllogictest {s} {s}", .{ version_string, platform_string }));
                cmd.addArgs(&.{ "uv", "run", "--python=3.12", "--with" });
                cmd.addFileArg(sqllogictest);
                cmd.addArgs(&.{ "--with", b.fmt("duckdb=={s}", .{@tagName(duckdb_version)}) });
                cmd.addArgs(&.{ "python3", "-m", "duckdb_sqllogictest" });
                cmd.addArgs(&.{ "--test-dir", "test" });
                cmd.addArg("--external-extension");
                cmd.addFileArg(ext_path);

                test_step.dependOn(&cmd.step);
            }

            check_step.dependOn(&ext.step);
        }
    }
}

const DuckDBVersion = enum {
    @"1.1.0", // First version with C API support
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",
    @"1.2.0",
    @"1.2.1",
    @"1.2.2",

    const all = std.enums.values(@This());

    fn toString(self: @This(), b: *Build) []const u8 {
        return b.fmt("v{s}", .{@tagName(self)});
    }

    fn headers(self: @This(), b: *Build) Build.LazyPath {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => b.dependency("libduckdb_1_1_3", .{}).path(""),
            .@"1.2.0", .@"1.2.1", .@"1.2.2" => b.dependency("libduckdb_1_2_2", .{}).path(""),
        };
    }

    fn extensionAPIVersion(self: @This()) [:0]const u8 {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => "v0.0.1",
            .@"1.2.0", .@"1.2.1", .@"1.2.2" => "v1.2.0",
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

    const all = std.enums.values(@This());

    fn toString(self: @This()) [:0]const u8 {
        return @tagName(self);
    }

    fn target(self: @This(), b: *Build) Build.ResolvedTarget {
        const manylinux2014_glibc_version = std.SemanticVersion{ .major = 2, .minor = 17, .patch = 0 };

        return b.resolveTargetQuery(switch (self) {
            .linux_amd64 => .{
                .os_tag = .linux,
                .cpu_arch = .x86_64,
                .abi = .gnu,
            },
            .linux_amd64_gcc4 => .{
                .os_tag = .linux,
                .cpu_arch = .x86_64,
                .abi = .gnu,
                .glibc_version = manylinux2014_glibc_version,
            },
            .linux_arm64 => .{
                .os_tag = .linux,
                .cpu_arch = .aarch64,
                .abi = .gnu,
            },
            .linux_arm64_gcc4 => .{
                .os_tag = .linux,
                .cpu_arch = .aarch64,
                .abi = .gnu,
                .glibc_version = manylinux2014_glibc_version,
            },
            .osx_amd64 => .{
                .os_tag = .macos,
                .cpu_arch = .x86_64,
                .abi = .none,
            },
            .osx_arm64 => .{
                .os_tag = .macos,
                .cpu_arch = .aarch64,
                .abi = .none,
            },
            .windows_amd64 => .{
                .os_tag = .windows,
                .cpu_arch = .x86_64,
                .abi = .gnu, // TODO: Switch to msvc?
            },
            .windows_arm64 => .{
                .os_tag = .windows,
                .cpu_arch = .aarch64,
                .abi = .gnu, // TODO: Switch to msvc?
            },
        });
    }
};

fn detectGitVersion(b: *std.Build) ![]const u8 {
    var code: u8 = 0;
    const git_describe = try b.runAllowFail(&[_][]const u8{
        "git",
        "-C",
        b.build_root.path orelse ".",
        "describe",
        "--tags",
        "--match",
        "v[0-9]*",
        "--always",
    }, &code, .Ignore);

    return std.mem.trim(u8, git_describe, " \n\r");
}

const cflags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-Werror",
    "-fvisibility=hidden", // Avoid symbol clashes
};
