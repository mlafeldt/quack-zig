const std = @import("std");
const duckdb = @import("duckdb.zig");
const c = duckdb.c;

// const allocator = std.heap.raw_c_allocator;

// var D: duckdb.API = undefined;

// const quack_prefix = "Quack ";
// const quack_suffix = " 🐥";

// fn quack_function(_: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) callconv(.C) void {
//     const input_vector = D.data_chunk_get_vector(input, 0);
//     const input_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(D.vector_get_data(input_vector)));
//     const input_mask = D.vector_get_validity(input_vector);

//     D.vector_ensure_validity_writable(output);
//     const result_mask = D.vector_get_validity(output);

//     const num_rows = D.data_chunk_get_size(input);
//     for (0..num_rows) |row| {
//         if (!D.validity_row_is_valid(input_mask, row)) {
//             // name is NULL -> set result to NULL
//             D.validity_set_row_invalid(result_mask, row);
//             continue;
//         }

//         var name = input_data[row];
//         const name_str = D.string_t_data(&name);
//         const name_len = D.string_t_length(name);

//         const result_str = std.mem.concat(allocator, u8, &[_][]const u8{
//             quack_prefix,
//             name_str[0..name_len],
//             quack_suffix,
//         }) catch @panic("OOM");

//         D.vector_assign_string_element_len(output, row, @ptrCast(result_str), result_str.len);
//         allocator.free(result_str);
//     }
// }

pub const Connection = struct {
    conn: *c.duckdb_connection,
    api: duckdb_ext_api,

    const Self = @This();

    pub fn open(db: c.duckdb_database, api: duckdb_ext_api) !Self {
        var conn: c.duckdb_connection = null;
        if (api.duckdb_connect.?(db, &conn) == c.DuckDBError) {
            return error.ConnectFailed;
        }
        return .{ .conn = &conn, .api = api };
    }

    pub fn deinit(self: *const Self) void {
        self.api.duckdb_disconnect.?(self.conn);
    }
};

const duckdb_ext_api = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const Extension = struct {
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
    db: c.duckdb_database,
    api: duckdb_ext_api,
    conn: ?Connection,

    const Self = @This();

    const min_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
        c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
        c.DUCKDB_EXTENSION_API_VERSION_MINOR,
        c.DUCKDB_EXTENSION_API_VERSION_PATCH,
    });

    pub fn init(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Self {
        const db: c.duckdb_database = @ptrCast(access.get_database.?(info));

        const maybe_api: ?*const duckdb_ext_api = @ptrCast(@alignCast(access.get_api.?(info, min_api_version)));
        if (maybe_api == null) {
            return error.APIVersionNotSupported;
        }
        const api = maybe_api.?.*;

        const conn = try Connection.open(db, api);

        return .{
            .info = info,
            .access = access,
            .db = db,
            .api = api,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.conn) |conn| {
            conn.deinit();
        }
        self.* = undefined;
    }

    pub fn releaseConnection(self: *Extension) Connection {
        const connection = self.conn.?;
        self.conn = null;
        return connection;
    }

    pub fn set_error(self: Self, msg: [*:0]const u8) void {
        self.access.set_error.?(self.info, msg);
    }
};

export fn quack_init_c_api(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    var ext = Extension.init(info, access) catch |e| {
        std.log.err("Failed to initialize extension: {s}", .{@errorName(e)});
        return false;
    };
    defer ext.deinit();

    const conn = ext.releaseConnection();

    _ = conn;

    // var conn: c.duckdb_connection = null;
    // if (ext.api.duckdb_connect.?(ext.db, &conn) == c.DuckDBError) {
    //     ext.set_error("Failed to open connection to database");
    //     return false;
    // }
    // defer ext.api.duckdb_disconnect.?(&conn);

    // var func: c.duckdb_scalar_function = D.create_scalar_function();
    // defer D.destroy_scalar_function(&func);

    // D.scalar_function_set_name(func, "quack");

    // var typ = D.create_logical_type(c.DUCKDB_TYPE_VARCHAR);
    // defer D.destroy_logical_type(&typ);
    // D.scalar_function_add_parameter(func, typ);
    // D.scalar_function_set_return_type(func, typ);

    // D.scalar_function_set_function(func, quack_function);

    // if (D.register_scalar_function(conn, func) == c.DuckDBError) {
    //     access.set_error.?(info, "Failed to register scalar function");
    //     return false;
    // }

    return true;
}
