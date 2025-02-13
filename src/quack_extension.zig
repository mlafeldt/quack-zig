const std = @import("std");
const c_allocator = std.heap.raw_c_allocator;

const Extension = @import("extension.zig");
const ScalarFunction = Extension.ScalarFunction;
const c = Extension.c;
const api = &Extension.api;

export fn quack_init_c_api(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    var ext = Extension.init(c_allocator, info, access) catch return false;
    defer ext.deinit();

    var func = ScalarFunction("quack", quack_function).create();
    defer func.deinit();

    ext.registerScalarFunction(func.ptr) catch return false;

    return true;
}

fn quack_function(_: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) callconv(.C) void {
    const quack_prefix = "Quack ";
    const quack_suffix = " 🐥";

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

        const result_str = std.mem.concat(c_allocator, u8, &[_][]const u8{
            quack_prefix,
            name_str[0..name_len],
            quack_suffix,
        }) catch @panic("OOM");

        api.duckdb_vector_assign_string_element_len.?(output, row, @ptrCast(result_str), result_str.len);
        c_allocator.free(result_str);
    }
}
