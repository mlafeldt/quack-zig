const std = @import("std");

pub fn detect(b: *std.Build) ![]const u8 {
    var code: u8 = undefined;
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
