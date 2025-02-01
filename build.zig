const std = @import("std");
const Build = std.Build;
const buildpkg = @import("build/main.zig");

pub fn build(b: *Build) !void {
    const config = try buildpkg.Config.init(b, "quack");
    std.log.debug("config: {any}", .{config});

    const libduckdb = try buildpkg.Libduckdb.init(b, &config);
    std.log.debug("libduckdb: {any}", .{libduckdb});

    const ext_version = buildpkg.GitVersion.detect(b) catch "n/a";

    const test_step = b.step("test", "Run SQL logic tests");

    const metadata_script = b.dependency("extension_ci_tools", .{}).path("scripts/append_extension_metadata.py");
    const sqllogictest = b.dependency("sqllogictest", .{}).path("");

    for (config.duckdb_versions) |duckdb_version| {
        const version_string = duckdb_version.string(b);
        const duckdb_headers = duckdb_version.headers(b);

        for (config.platforms) |platform| {
            const platform_string = platform.string();
            const target = platform.target(b);

            const ext = b.addSharedLibrary(.{
                .name = "quack",
                .target = target,
                .optimize = config.optimize,
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
                .custom = if (config.flat) platform_string else b.fmt("{s}/{s}", .{ version_string, platform_string }),
            }, filename);
            install_file.step.name = b.fmt("install {s} {s}", .{ version_string, platform_string });
            b.getInstallStep().dependOn(&install_file.step);

            if (config.install_headers) {
                const header_dirs = [_]Build.LazyPath{
                    duckdb_headers,
                    // Add more header directories here
                };
                for (header_dirs) |dir| {
                    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                        .source_dir = dir,
                        .include_extensions = &.{"h"},
                        .install_dir = if (config.flat) .header else .{ .custom = b.fmt("{s}/include", .{version_string}) },
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
