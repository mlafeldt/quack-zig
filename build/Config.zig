const Config = @This();

const std = @import("std");
const Build = std.Build;

ext_name: []const u8,
optimize: std.builtin.OptimizeMode,
duckdb_versions: []const Version,
platforms: []const Platform,
install_headers: bool,
flat: bool,

const Version = enum {
    @"1.1.0", // First version with C API support
    @"1.1.1",
    @"1.1.2",
    @"1.1.3",
    @"1.2.0",

    const all = std.enums.values(@This());

    fn string(self: @This(), b: *Build) []const u8 {
        return b.fmt("v{s}", .{@tagName(self)});
    }

    fn headers(self: @This(), b: *Build) Build.LazyPath {
        return switch (self) {
            .@"1.1.0", .@"1.1.1", .@"1.1.2", .@"1.1.3" => b.dependency("libduckdb_1_1_3", .{}).path(""),
            .@"1.2.0" => b.dependency("libduckdb_headers", .{}).path("1.2.0"),
        };
    }

    fn extensionAPIVersion(self: @This()) [:0]const u8 {
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

    const all = std.enums.values(@This());

    fn string(self: @This()) [:0]const u8 {
        return @tagName(self);
    }

    fn target(self: @This(), b: *Build) Build.ResolvedTarget {
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

pub fn init(b: *std.Build, ext_name: []const u8) !Config {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_versions = b.option([]const Version, "duckdb-version", "DuckDB version(s) to build for (default: all)") orelse Version.all;
    const platforms = b.option([]const Platform, "platform", "DuckDB platform(s) to build for (default: all)") orelse Platform.all;
    const install_headers = b.option(bool, "install-headers", "Install DuckDB C headers") orelse false;
    const flat = b.option(bool, "flat", "Install files without DuckDB version prefix") orelse false;

    if (flat and duckdb_versions.len > 1) {
        std.zig.fatal("-Dflat requires passing a specific DuckDB version", .{});
    }

    return .{
        .ext_name = ext_name,
        .optimize = optimize,
        .duckdb_versions = duckdb_versions,
        .platforms = platforms,
        .install_headers = install_headers,
        .flat = flat,
    };
}
