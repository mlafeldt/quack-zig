const std = @import("std");
const c = @import("duckdb_extension_v1.1.3");

const ext_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

export fn quack_init_c_api(
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
) bool {
    const minimum_api_version = "v0.0.1";
    const maybe_api: ?*const c.duckdb_ext_api_v0 = @ptrCast(@alignCast(access.get_api.?(info, minimum_api_version)));
    const api = maybe_api orelse return false;

    const db: c.duckdb_database = @ptrCast(access.get_database.?(info));
    var conn: c.duckdb_connection = undefined;
    if (api.duckdb_connect.?(db, &conn) == c.DuckDBError) {
        access.set_error.?(info, "Failed to open connection to database");
        return false;
    }
    defer api.duckdb_disconnect.?(&conn);

    std.debug.print("Extension API version: {s}\n", .{ext_api_version});

    return true;
}
