const std = @import("std");
pub const c = @import("duckdb_capi");

const Allocator = std.mem.Allocator;
const DuckDBError = c.DuckDBError;

pub const API = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const DB = struct {
    inner: *c.duckdb_database,

    const Self = @This();

    pub fn provided(db: *c.duckdb_database) Self {
        return .{ .inner = db };
    }
};

pub const Connection = struct {
    allocator: Allocator,
    api: API,
    inner: *c.duckdb_connection,

    const Self = @This();

    pub fn open(allocator: Allocator, db: DB) !Self {
        const conn = try allocator.create(c.duckdb_connection);
        errdefer allocator.destroy(conn);

        if (api.duckdb_connect.?(db.inner.*, conn) == DuckDBError) {
            return error.ConnectError;
        }

        return .{
            .allocator = allocator,
            .api = api,
            .inner = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        const conn = self.inner;
        self.api.duckdb_disconnect.?(conn);
        self.allocator.destroy(conn);
        self.* = undefined;
    }
};

const Extension = @This();

// SAFETY: api is initialized in init
pub var api: API = undefined;

info: c.duckdb_extension_info,
access: *c.duckdb_extension_access,
db: DB,
conn: Connection,

pub fn init(allocator: Allocator, info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Extension {
    api = try getAPI(info, access);

    const db = DB.provided(access.get_database.?(info));
    const conn = Connection.open(allocator, db) catch |e| {
        access.set_error.?(info, "Failed to open connection to database");
        return e;
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

fn getAPI(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !API {
    const min_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
        c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
        c.DUCKDB_EXTENSION_API_VERSION_MINOR,
        c.DUCKDB_EXTENSION_API_VERSION_PATCH,
    });

    const maybe_api: ?*const API = @ptrCast(@alignCast(access.get_api.?(info, min_api_version)));
    if (maybe_api == null) {
        return error.APIVersionNotSupported;
    }
    return maybe_api.?.*;
}

pub fn registerScalarFunction(
    self: *Extension,
    func: ScalarFunction,
) !void {
    if (api.duckdb_register_scalar_function.?(self.conn.inner.*, func.ptr) == DuckDBError) {
        self.access.set_error.?(self.info, "Failed to register scalar function");
        return error.RegisterScalarFunctionError;
    }
}

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
    boolean = c.DUCKDB_TYPE_BOOLEAN,
    varchar = c.DUCKDB_TYPE_VARCHAR,
};

pub const LogicalType = struct {
    duckdb_type: DuckDBType,
    ptr: c.duckdb_logical_type,

    const Self = @This();

    pub fn boolean() LogicalType {
        return Self.init(DuckDBType.boolean);
    }

    pub fn varchar() LogicalType {
        return Self.init(DuckDBType.varchar);
    }

    pub fn init(duckdb_type: DuckDBType) Self {
        const ptr = api.duckdb_create_logical_type.?(@intFromEnum(duckdb_type));
        return .{ .duckdb_type = duckdb_type, .ptr = ptr };
    }

    pub fn deinit(self: *LogicalType) void {
        api.duckdb_destroy_logical_type.?(&self.ptr);
        self.* = undefined;
    }
};
