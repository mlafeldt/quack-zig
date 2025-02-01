const std = @import("std");
const Build = std.Build;
const buildpkg = @import("build/main.zig");

pub fn build(b: *Build) !void {
    const config = buildpkg.Config.init(b, "quack");

    std.log.info("{any}", .{config});
}
