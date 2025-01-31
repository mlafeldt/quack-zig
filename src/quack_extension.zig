const std = @import("std");
const c = @import("duckdb_extension");

const version_string = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

// Add the internal initialization function
fn quack_init_c_api_internal(
    connection: c.duckdb_connection,
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
) bool {
    std.debug.print("API version: {s}\n", .{version_string});
    // Your extension initialization logic goes here
    _ = connection;
    _ = info;
    _ = access;
    return true;
}

// Modified entry point with full functionality
export fn quack_init_c_api(
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
) bool {
    // API version check and initialization
    const get_api_fn = access.get_api orelse return false;
    const api = get_api_fn(info, "v0.0.1") orelse return false;
    _ = api;

    // Database connection setup
    const get_db_fn = access.get_database orelse return false;
    const db = get_db_fn(info);

    var conn: c.duckdb_connection = undefined;
    if (c.duckdb_connect(db, &conn) == c.DuckDBError.DuckDBError) {
        access.set_error(info, "Failed to open connection to database");
        return false;
    }

    // Call internal implementation
    const init_result = quack_init_c_api_internal(conn, info, access);

    // Cleanup connection
    c.duckdb_disconnect(&conn);
    return init_result;
}
