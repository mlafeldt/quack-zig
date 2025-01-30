const std = @import("std");
const c = @import("duckdb_extension");

const version_string = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

export fn quack_init_c_api() bool {
    std.debug.print("API version: {s}\n", .{version_string});
    return true;
}
