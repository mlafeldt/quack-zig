// Props to:
// https://github.com/karlseguin/zuckdb.zig
// https://github.com/softprops/zig-duckdb-ext

const std = @import("std");
pub const c = @import("duckdb_capi");

const assert = std.debug.assert;
const DuckDBError = c.DuckDBError;
const Extension = @This();

pub const API = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

// SAFETY: api is initialized in init
pub var api: API = undefined;

info: c.duckdb_extension_info,
access: *c.duckdb_extension_access,
db: DB,
conn: Connection,

pub fn init(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Extension {
    const maybe_api: ?*const API = @ptrCast(@alignCast(access.get_api.?(info, api_version)));
    if (maybe_api == null) {
        // DuckDB will log an error, no need to call set_error
        return error.GetAPIError;
    }
    api = maybe_api.?.*;

    const maybe_db = access.get_database.?(info);
    if (maybe_db == null) {
        // DuckDB will log an error, no need to call set_error
        return error.GetDatabaseError;
    }
    const db = DB.provided(maybe_db.*);

    const conn = Connection.open(db) catch |err| {
        access.set_error.?(info, "Failed to open connection to database");
        return err;
    };

    return .{
        .info = info,
        .access = access,
        .db = db,
        .conn = conn,
    };
}

pub fn deinit(self: *Extension) void {
    self.conn.deinit();
    self.* = undefined;
}

pub fn setError(self: *Extension, msg: [*:0]const u8) void {
    self.access.set_error.?(self.info, msg);
}

pub fn registerScalarFunction(
    self: *Extension,
    func: ScalarFunction,
) !void {
    if (api.duckdb_register_scalar_function.?(self.conn.ptr, func.ptr) == DuckDBError) {
        self.setError("Failed to register scalar function");
        return error.RegisterScalarFunctionError;
    }
}

pub const DB = struct {
    ptr: c.duckdb_database,

    pub fn provided(db: c.duckdb_database) DB {
        return .{ .ptr = db };
    }
};

pub const Connection = struct {
    ptr: c.duckdb_connection,

    const Self = @This();

    pub fn open(db: DB) !Self {
        var conn: c.duckdb_connection = null;
        if (api.duckdb_connect.?(db.ptr, &conn) == DuckDBError) {
            return error.ConnectError;
        }
        assert(conn != null);
        return .{ .ptr = conn };
    }

    pub fn deinit(self: *Self) void {
        api.duckdb_disconnect.?(&self.ptr);
        self.* = undefined;
    }
};

pub const ScalarFunction = struct {
    name: [*:0]const u8,
    func: c.duckdb_scalar_function_t,
    ptr: c.duckdb_scalar_function,

    const Self = @This();

    pub fn init(
        name: [*:0]const u8,
        params: []const LogicalType,
        return_type: LogicalType,
        func: c.duckdb_scalar_function_t,
    ) Self {
        const ptr = api.duckdb_create_scalar_function.?();
        assert(ptr != null);

        api.duckdb_scalar_function_set_name.?(ptr, name);
        for (params) |param| {
            api.duckdb_scalar_function_add_parameter.?(ptr, param.ptr);
        }
        api.duckdb_scalar_function_set_return_type.?(ptr, return_type.ptr);
        api.duckdb_scalar_function_set_function.?(ptr, func);

        return .{
            .name = name,
            .func = func,
            .ptr = ptr,
        };
    }

    pub fn deinit(self: *Self) void {
        api.duckdb_destroy_scalar_function.?(&self.ptr);
        self.* = undefined;
    }
};

pub const DuckDBType = enum(c.enum_DUCKDB_TYPE) {
    invalid = c.DUCKDB_TYPE_INVALID,
    boolean = c.DUCKDB_TYPE_BOOLEAN,
    tinyint = c.DUCKDB_TYPE_TINYINT,
    smallint = c.DUCKDB_TYPE_SMALLINT,
    integer = c.DUCKDB_TYPE_INTEGER,
    bigint = c.DUCKDB_TYPE_BIGINT,
    utinyint = c.DUCKDB_TYPE_UTINYINT,
    usmallint = c.DUCKDB_TYPE_USMALLINT,
    uinteger = c.DUCKDB_TYPE_UINTEGER,
    ubigint = c.DUCKDB_TYPE_UBIGINT,
    float = c.DUCKDB_TYPE_FLOAT,
    double = c.DUCKDB_TYPE_DOUBLE,
    timestamp = c.DUCKDB_TYPE_TIMESTAMP,
    date = c.DUCKDB_TYPE_DATE,
    time = c.DUCKDB_TYPE_TIME,
    interval = c.DUCKDB_TYPE_INTERVAL,
    hugeint = c.DUCKDB_TYPE_HUGEINT,
    uhugeint = c.DUCKDB_TYPE_UHUGEINT,
    varchar = c.DUCKDB_TYPE_VARCHAR,
    blob = c.DUCKDB_TYPE_BLOB,
    decimal = c.DUCKDB_TYPE_DECIMAL,
    timestamp_s = c.DUCKDB_TYPE_TIMESTAMP_S,
    timestamp_ms = c.DUCKDB_TYPE_TIMESTAMP_MS,
    timestamp_ns = c.DUCKDB_TYPE_TIMESTAMP_NS,
    @"enum" = c.DUCKDB_TYPE_ENUM,
    list = c.DUCKDB_TYPE_LIST,
    @"struct" = c.DUCKDB_TYPE_STRUCT,
    map = c.DUCKDB_TYPE_MAP,
    array = c.DUCKDB_TYPE_ARRAY,
    uuid = c.DUCKDB_TYPE_UUID,
    @"union" = c.DUCKDB_TYPE_UNION,
    bit = c.DUCKDB_TYPE_BIT,
    time_tz = c.DUCKDB_TYPE_TIME_TZ,
    timestamp_tz = c.DUCKDB_TYPE_TIMESTAMP_TZ,
    any = c.DUCKDB_TYPE_ANY,
    varint = c.DUCKDB_TYPE_VARINT,
    sqlnull = c.DUCKDB_TYPE_SQLNULL,
};

pub const LogicalType = struct {
    duckdb_type: DuckDBType,
    ptr: c.duckdb_logical_type,

    const Self = @This();
    const jsonTypeName = "JSON";

    // TODO: add more constructors

    pub fn boolean() LogicalType {
        return Self.init(DuckDBType.boolean);
    }

    pub fn varchar() LogicalType {
        return Self.init(DuckDBType.varchar);
    }

    pub fn JSON() LogicalType {
        const typ = Self.init(DuckDBType.varchar);
        api.duckdb_logical_type_set_alias.?(typ.ptr, jsonTypeName);
        return typ;
    }

    pub fn isJSON(self: Self) bool {
        if (self.duckdb_type != DuckDBType.varchar) return false;
        const alias = api.duckdb_logical_type_get_alias.?(self.ptr);
        return alias != null and std.mem.eql(u8, alias, jsonTypeName);
    }

    pub fn init(duckdb_type: DuckDBType) Self {
        const ptr = api.duckdb_create_logical_type.?(@intFromEnum(duckdb_type));
        assert(ptr != null);
        return .{ .duckdb_type = duckdb_type, .ptr = ptr };
    }

    pub fn deinit(self: *LogicalType) void {
        api.duckdb_destroy_logical_type.?(&self.ptr);
        self.* = undefined;
    }
};
