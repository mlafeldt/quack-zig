const std = @import("std");
const Build = std.Build;
const buildpkg = @import("build/main.zig");

pub fn build(b: *Build) !void {
    const config = try buildpkg.Config.init(b, "quack");
    std.log.debug("config: {any}", .{config});

    const libduckdb = try buildpkg.Libduckdb.init(b, &config);
    std.log.debug("libduckdb: {any}", .{libduckdb});

    const git_version = buildpkg.GitVersion.detect(b) catch "n/a";
    std.log.debug("git_version: {s}", .{git_version});
}
