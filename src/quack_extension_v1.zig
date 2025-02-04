const std = @import("std");
const c = @import("duckdb_extension_v1");

const allocator = std.heap.raw_c_allocator;

const ExtensionAPI = c.duckdb_ext_api_v1;
var api: ExtensionAPI = .{};
const minimum_api_version = "v1.2.0";

const quack_prefix = "Quack ";
const quack_suffix = " 🐥";

fn quack_function(info: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) callconv(.C) void {
    _ = info;

    const input_vector = api.duckdb_data_chunk_get_vector.?(input, 0);
    const input_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(api.duckdb_vector_get_data.?(input_vector)));
    const input_mask = api.duckdb_vector_get_validity.?(input_vector);

    api.duckdb_vector_ensure_validity_writable.?(output);
    const result_mask = api.duckdb_vector_get_validity.?(output);

    const num_rows = api.duckdb_data_chunk_get_size.?(input);
    for (0..num_rows) |row| {
        if (!api.duckdb_validity_row_is_valid.?(input_mask, row)) {
            // name is NULL -> set result to NULL
            api.duckdb_validity_set_row_invalid.?(result_mask, row);
            continue;
        }

        var name = input_data[row];
        const name_str = api.duckdb_string_t_data.?(&name);
        const name_len = api.duckdb_string_t_length.?(name);

        const result_str = std.mem.concat(allocator, u8, &[_][]const u8{
            quack_prefix,
            name_str[0..name_len],
            quack_suffix,
        }) catch @panic("OOM");

        api.duckdb_vector_assign_string_element_len.?(output, row, @ptrCast(result_str), result_str.len);
        allocator.free(result_str);
    }
}

export fn quack_init_c_api(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    const maybe_api: ?*const ExtensionAPI = @ptrCast(@alignCast(access.get_api.?(info, minimum_api_version)));
    api = (maybe_api orelse return false).*;

    const db: c.duckdb_database = @ptrCast(access.get_database.?(info));
    var conn: c.duckdb_connection = undefined;
    if (api.duckdb_connect.?(db, &conn) == c.DuckDBError) {
        access.set_error.?(info, "Failed to open connection to database");
        return false;
    }
    defer api.duckdb_disconnect.?(&conn);

    var func: c.duckdb_scalar_function = api.duckdb_create_scalar_function.?();
    defer api.duckdb_destroy_scalar_function.?(&func);

    api.duckdb_scalar_function_set_name.?(func, "quack");

    var typ = api.duckdb_create_logical_type.?(c.DUCKDB_TYPE_VARCHAR);
    defer api.duckdb_destroy_logical_type.?(&typ);
    api.duckdb_scalar_function_add_parameter.?(func, typ);
    api.duckdb_scalar_function_set_return_type.?(func, typ);

    api.duckdb_scalar_function_set_function.?(func, quack_function);

    if (api.duckdb_register_scalar_function.?(conn, func) == c.DuckDBError) {
        access.set_error.?(info, "Failed to register scalar function");
        return false;
    }

    return true;
}
