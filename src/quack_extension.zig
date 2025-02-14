const std = @import("std");
const allocator = std.heap.raw_c_allocator;

const Extension = @import("extension.zig");
const ScalarFunction = Extension.ScalarFunction;
const D = &Extension.api;
const c = Extension.c;

export fn quack_init_c_api(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) bool {
    loadExtension(info, access) catch |err| {
        std.log.err("Failed to load extension: {}", .{err});
        return false;
    };
    return true;
}

fn loadExtension(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !void {
    var ext = try Extension.init(allocator, info, access);
    defer ext.deinit();

    var func = ScalarFunction("quack", quackFunction).create();
    defer func.deinit();
    try ext.registerScalarFunction(func.ptr);
}

fn quackFunction(_: c.duckdb_function_info, input: c.duckdb_data_chunk, output: c.duckdb_vector) callconv(.C) void {
    const quack_prefix = "Quack ";
    const quack_suffix = " 🐥";

    const input_vector = D.duckdb_data_chunk_get_vector.?(input, 0);
    const input_data: [*]c.duckdb_string_t = @ptrCast(@alignCast(D.duckdb_vector_get_data.?(input_vector)));
    const input_mask = D.duckdb_vector_get_validity.?(input_vector);

    D.duckdb_vector_ensure_validity_writable.?(output);
    const result_mask = D.duckdb_vector_get_validity.?(output);

    const num_rows = D.duckdb_data_chunk_get_size.?(input);
    for (0..num_rows) |row| {
        if (!D.duckdb_validity_row_is_valid.?(input_mask, row)) {
            // name is NULL -> set result to NULL
            D.duckdb_validity_set_row_invalid.?(result_mask, row);
            continue;
        }

        var name = input_data[row];
        const name_str = D.duckdb_string_t_data.?(&name);
        const name_len = D.duckdb_string_t_length.?(name);

        const result_str = std.mem.concat(allocator, u8, &[_][]const u8{
            quack_prefix,
            name_str[0..name_len],
            quack_suffix,
        }) catch @panic("OOM");

        D.duckdb_vector_assign_string_element_len.?(output, row, @ptrCast(result_str), result_str.len);
        allocator.free(result_str);
    }
}
