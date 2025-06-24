const std = @import("std");
const c = @cImport({
    @cInclude("duckdb_extension.h");
});

const API = if (c.DUCKDB_EXTENSION_API_VERSION_MAJOR == 0 and
    c.DUCKDB_EXTENSION_API_VERSION_MINOR == 0 and
    c.DUCKDB_EXTENSION_API_VERSION_PATCH == 1)
    c.duckdb_ext_api_v0
else if (c.DUCKDB_EXTENSION_API_VERSION_MAJOR == 1 and
    c.DUCKDB_EXTENSION_API_VERSION_MINOR == 2 and
    c.DUCKDB_EXTENSION_API_VERSION_PATCH == 0)
    c.duckdb_ext_api_v1
else
    @compileError("Unsupported DuckDB API version");
pub var api: API = undefined;

export fn init(conn: c.duckdb_connection, info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    const api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
        c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
        c.DUCKDB_EXTENSION_API_VERSION_MINOR,
        c.DUCKDB_EXTENSION_API_VERSION_PATCH,
    });
    const maybe_api: ?*const API = @ptrCast(@alignCast(access.get_api.?(info, api_version)));
    api = (maybe_api orelse {
        access.set_error.?(info, "Failed to get API");
        return false;
    }).*;

    var func = api.duckdb_create_scalar_function.?(info, "quack").?;
    api.duckdb_scalar_function_set_name.?(func, "quack");

    var typ = api.duckdb_create_logical_type.?(c.DUCKDB_TYPE_VARCHAR).?;
    api.duckdb_scalar_function_add_parameter.?(func, typ);
    api.duckdb_scalar_function_set_return_type.?(func, typ);
    api.duckdb_destroy_logical_type.?(&typ);

    api.duckdb_scalar_function_set_function.?(func, quack_function);
    if (api.duckdb_register_scalar_function.?(conn, func) == c.DuckDBError) {
        access.set_error.?(info, "Failed to register scalar function");
        return false;
    }
    api.duckdb_destroy_scalar_function.?(&func);
    return true;
}

const quack_prefix = "Quack ";
const quack_suffix = " 🐥";
fn quack_function(
    info: c.duckdb_function_info,
    input: c.duckdb_data_chunk,
    output: c.duckdb_vector,
) callconv(.c) void {
    const input_vector = api.duckdb_data_chunk_get_vector.?(input, 0);
    const input_data: [*]c.duckdb_string_t = @alignCast(@ptrCast(api.duckdb_vector_get_data.?(input_vector)));
    const input_mask = api.duckdb_vector_get_validity.?(input_vector);

    api.duckdb_vector_ensure_validity_writable.?(output);
    const result_mask = api.duckdb_vector_get_validity.?(output);

    const num_rows = api.duckdb_data_chunk_get_size.?(input);
    for (0..@intCast(num_rows)) |row| {
        if (!api.duckdb_validity_row_is_valid.?(input_mask, row)) {
            // name is NULL -> set result to NULL
            api.duckdb_validity_set_row_invalid.?(result_mask, row);
            continue;
        }

        var name = input_data[row];
        const name_slice = api.duckdb_string_t_data.?(&name)[0..api.duckdb_string_t_length.?(name)];

        const res_len = quack_prefix.len + name_slice.len + quack_suffix.len;
        const res: [*]u8 = @ptrCast(api.duckdb_malloc.?(res_len) orelse {
            api.duckdb_scalar_function_set_error.?(info, "Failed to allocate memory for result");
            return;
        });

        @memcpy(res, quack_prefix);
        @memcpy(res[quack_prefix.len..], name_slice);
        @memcpy(res[quack_prefix.len + name_slice.len ..], quack_suffix);

        api.duckdb_vector_assign_string_element_len.?(output, row, res, res_len);
        api.duckdb_free.?(res);
    }
}
