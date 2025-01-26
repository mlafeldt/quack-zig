#include <duckdb_extension.h>
#include <string.h>  // memcpy

DUCKDB_EXTENSION_EXTERN

// Workaround for missing struct tag in DUCKDB_EXTENSION_ENTRYPOINT (DuckDB 1.1.x)
typedef struct duckdb_extension_access duckdb_extension_access;

#if DUCKDB_EXTENSION_API_VERSION_MAJOR >= 1
#define EXTENSION_RETURN(result) return (result)
#else
#define EXTENSION_RETURN(result) return
#endif

#define QUACK_PREFIX "Quack "
#define QUACK_SUFFIX " 🐥"

static void quack_function(duckdb_function_info info, duckdb_data_chunk input, duckdb_vector output) {
    const size_t prefix_len = strlen(QUACK_PREFIX);
    const size_t suffix_len = strlen(QUACK_SUFFIX);

    duckdb_vector input_vector = duckdb_data_chunk_get_vector(input, 0);
    duckdb_string_t *input_data = (duckdb_string_t *)duckdb_vector_get_data(input_vector);
    uint64_t *input_mask = duckdb_vector_get_validity(input_vector);

    duckdb_vector_ensure_validity_writable(output);
    uint64_t *result_mask = duckdb_vector_get_validity(output);

    idx_t num_rows = duckdb_data_chunk_get_size(input);
    for (idx_t row = 0; row < num_rows; row++) {
        if (!duckdb_validity_row_is_valid(input_mask, row)) {
            // name is NULL -> set result to NULL
            duckdb_validity_set_row_invalid(result_mask, row);
            continue;
        }

        duckdb_string_t name = input_data[row];
        const char *name_str = duckdb_string_t_data(&name);
        size_t name_len = duckdb_string_t_length(name);

        size_t res_len = prefix_len + name_len + suffix_len;
        char *res = duckdb_malloc(res_len);
        if (res == NULL) {
            duckdb_scalar_function_set_error(info, "Failed to allocate memory for result");
            return;
        }

        memcpy(res, QUACK_PREFIX, prefix_len);
        memcpy(res + prefix_len, name_str, name_len);
        memcpy(res + prefix_len + name_len, QUACK_SUFFIX, suffix_len);

        duckdb_vector_assign_string_element_len(output, row, res, res_len);
        duckdb_free(res);
    }
}

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection conn, duckdb_extension_info info, duckdb_extension_access *access) {
    duckdb_scalar_function func = duckdb_create_scalar_function();
    duckdb_scalar_function_set_name(func, "quack");

    duckdb_logical_type typ = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_scalar_function_add_parameter(func, typ);
    duckdb_scalar_function_set_return_type(func, typ);
    duckdb_destroy_logical_type(&typ);

    duckdb_scalar_function_set_function(func, quack_function);

    if (duckdb_register_scalar_function(conn, func) == DuckDBError) {
        access->set_error(info, "Failed to register scalar function");
        EXTENSION_RETURN(false);
    }

    duckdb_destroy_scalar_function(&func);
    EXTENSION_RETURN(true);
}
