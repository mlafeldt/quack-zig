const std = @import("std");
const Build = std.Build;
const DuckDB = @import("duckdb.zig");

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_versions = b.option([]const DuckDB.Version, "duckdb-version", "DuckDB version(s) to build for (default: all)") orelse DuckDB.Version.all;
    const platforms = b.option([]const DuckDB.Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse DuckDB.Platform.all;
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;
    const flat = b.option(bool, "flat", "Install files without DuckDB version prefix") orelse false;

    if (flat and duckdb_versions.len > 1) {
        std.zig.fatal("-Dflat requires passing a specific DuckDB version", .{});
    }

    return DuckDB.buildExtension(b, .{
        .ext_name = "quack",
        .optimize = optimize,
        .duckdb_versions = duckdb_versions,
        .platforms = platforms,
        .install_headers = install_headers,
        .flat = flat,
    });
}
