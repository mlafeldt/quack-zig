const Libduckdb = @This();

const std = @import("std");
const Build = std.Build;
const Config = @import("Config.zig");

config: *const Config,

pub fn init(b: *std.Build, cfg: *const Config) !Libduckdb {
    _ = b;
    return Libduckdb{
        .config = cfg,
    };
}
