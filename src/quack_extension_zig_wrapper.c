#include <duckdb_extension.h>

DUCKDB_EXTENSION_EXTERN

// Workaround for missing struct tag in DUCKDB_EXTENSION_ENTRYPOINT (DuckDB 1.1.x)
typedef struct duckdb_extension_access duckdb_extension_access;

#if DUCKDB_EXTENSION_API_VERSION_MAJOR >= 1
#define EXTENSION_RETURN(result) return (result)
#else
#define EXTENSION_RETURN(result) return
#endif

extern bool init(duckdb_connection conn, duckdb_extension_info info, duckdb_extension_access *access);

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection conn, duckdb_extension_info info, duckdb_extension_access *access) {
    if (!init(conn, info, access)) {
        EXTENSION_RETURN(false);
    }
    EXTENSION_RETURN(true);
}
