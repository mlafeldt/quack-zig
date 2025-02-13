const std = @import("std");
const Extension = @import("extension.zig").Extension;
const c = @import("extension.zig").c;

export fn quack_init_c_api(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    var ext = Extension.init(std.heap.raw_c_allocator, info, access) catch return false;
    defer ext.deinit();

    const api = ext.getAPI();

    var func: c.duckdb_scalar_function = api.duckdb_create_scalar_function.?();
    defer api.duckdb_destroy_scalar_function.?(&func);

    // api.duckdb_scalar_function_set_name.?(func, "quack");

    // var typ = api.duckdb_create_logical_type(c.DUCKDB_TYPE_VARCHAR);
    // defer api.duckdb_destroy_logical_type(&typ);
    // api.duckdb_scalar_function_add_parameter(func, typ);
    // api.duckdb_scalar_function_set_return_type(func, typ);

    // api.scalar_function_set_function(func, quack_function);

    // if (api.duckdb_register_scalar_function(ext.conn.conn, func) == c.DuckDBError) {
    //     access.set_error.?(info, "Failed to register scalar function");
    //     return false;
    // }

    return true;
}

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
