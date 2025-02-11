const std = @import("std");
pub const c = @import("duckdb_capi");

const minimum_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

comptime {
    if (!std.mem.eql(u8, minimum_api_version, @import("build_options").ext_api_version))
        @compileError("DuckDB extension API version mismatch");
}

const duckdb_ext_api = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const API = struct {
    raw: *const duckdb_ext_api,

    duckdb_connect: *const fn (c.duckdb_database, [*c]c.duckdb_connection) callconv(.C) c.duckdb_state,
    duckdb_disconnect: *const fn ([*c]c.duckdb_connection) callconv(.C) void,

    duckdb_string_t_length: *const fn (c.duckdb_string_t) callconv(.C) u32,
    duckdb_string_t_data: *const fn ([*c]c.duckdb_string_t) callconv(.C) [*c]const u8,

    duckdb_create_logical_type: *const fn (c.duckdb_type) callconv(.C) c.duckdb_logical_type,
    duckdb_destroy_logical_type: *const fn ([*c]c.duckdb_logical_type) callconv(.C) void,

    duckdb_data_chunk_get_vector: *const fn (c.duckdb_data_chunk, c.idx_t) callconv(.C) c.duckdb_vector,
    duckdb_data_chunk_get_size: *const fn (c.duckdb_data_chunk) callconv(.C) c.idx_t,

    duckdb_vector_get_data: *const fn (c.duckdb_vector) callconv(.C) ?*anyopaque,
    duckdb_vector_get_validity: *const fn (c.duckdb_vector) callconv(.C) [*c]u64,
    duckdb_vector_ensure_validity_writable: *const fn (c.duckdb_vector) callconv(.C) void,
    duckdb_vector_assign_string_element_len: *const fn (c.duckdb_vector, c.idx_t, [*c]const u8, c.idx_t) callconv(.C) void,

    duckdb_validity_row_is_valid: *const fn ([*c]u64, c.idx_t) callconv(.C) bool,
    duckdb_validity_set_row_invalid: *const fn ([*c]u64, c.idx_t) callconv(.C) void,

    duckdb_create_scalar_function: *const fn (...) callconv(.C) c.duckdb_scalar_function,
    duckdb_destroy_scalar_function: *const fn ([*c]c.duckdb_scalar_function) callconv(.C) void,
    duckdb_scalar_function_set_name: *const fn (c.duckdb_scalar_function, [*c]const u8) callconv(.C) void,
    duckdb_scalar_function_add_parameter: *const fn (c.duckdb_scalar_function, c.duckdb_logical_type) callconv(.C) void,
    duckdb_scalar_function_set_return_type: *const fn (c.duckdb_scalar_function, c.duckdb_logical_type) callconv(.C) void,
    duckdb_scalar_function_set_function: *const fn (c.duckdb_scalar_function, *const fn (c.duckdb_function_info, c.duckdb_data_chunk, c.duckdb_vector) callconv(.C) void) callconv(.C) void,
    duckdb_register_scalar_function: *const fn (c.duckdb_connection, c.duckdb_scalar_function) callconv(.C) c.duckdb_state,
};

var extension_api: ?API = null;

pub fn init(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) ?API {
    if (extension_api != null) return extension_api;

    const maybe_api: ?*const duckdb_ext_api = @ptrCast(@alignCast(access.get_api.?(info, minimum_api_version)));
    if (maybe_api) |api| {
        extension_api = .{
            .raw = api,

            .duckdb_connect = api.duckdb_connect.?,
            .duckdb_disconnect = api.duckdb_disconnect.?,

            .duckdb_string_t_length = api.duckdb_string_t_length.?,
            .duckdb_string_t_data = api.duckdb_string_t_data.?,

            .duckdb_create_logical_type = api.duckdb_create_logical_type.?,
            .duckdb_destroy_logical_type = api.duckdb_destroy_logical_type.?,

            .duckdb_data_chunk_get_vector = api.duckdb_data_chunk_get_vector.?,
            .duckdb_data_chunk_get_size = api.duckdb_data_chunk_get_size.?,

            .duckdb_vector_get_data = api.duckdb_vector_get_data.?,
            .duckdb_vector_get_validity = api.duckdb_vector_get_validity.?,
            .duckdb_vector_ensure_validity_writable = api.duckdb_vector_ensure_validity_writable.?,
            .duckdb_vector_assign_string_element_len = api.duckdb_vector_assign_string_element_len.?,

            .duckdb_validity_row_is_valid = api.duckdb_validity_row_is_valid.?,
            .duckdb_validity_set_row_invalid = api.duckdb_validity_set_row_invalid.?,

            .duckdb_create_scalar_function = api.duckdb_create_scalar_function.?,
            .duckdb_destroy_scalar_function = api.duckdb_destroy_scalar_function.?,
            .duckdb_scalar_function_set_name = api.duckdb_scalar_function_set_name.?,
            .duckdb_scalar_function_add_parameter = api.duckdb_scalar_function_add_parameter.?,
            .duckdb_scalar_function_set_return_type = api.duckdb_scalar_function_set_return_type.?,
            .duckdb_scalar_function_set_function = api.duckdb_scalar_function_set_function.?,
            .duckdb_register_scalar_function = api.duckdb_register_scalar_function.?,
        };
    }

    return extension_api;
}
