const std = @import("std");
pub const c = @import("duckdb_capi");

const Allocator = std.mem.Allocator;

const DuckDBError = c.DuckDBError;

const duckdb_ext_api = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

const min_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
    c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
    c.DUCKDB_EXTENSION_API_VERSION_MINOR,
    c.DUCKDB_EXTENSION_API_VERSION_PATCH,
});

pub var api: duckdb_ext_api = undefined;
pub var database: DB = undefined;

fn initAPI(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !void {
    database = DB.provided(access.get_database.?(info));

    const maybe_api: ?*const duckdb_ext_api = @ptrCast(@alignCast(access.get_api.?(info, min_api_version)));
    if (maybe_api == null) {
        return error.APIVersionNotSupported;
    }
    api = maybe_api.?.*;
}

pub const DB = struct {
    ptr: *c.duckdb_database,

    const Self = @This();

    pub fn provided(db: *c.duckdb_database) Self {
        return .{ .ptr = db };
    }
};

pub const Connection = struct {
    allocator: Allocator,
    conn: *c.duckdb_connection,

    const Self = @This();

    pub fn init(allocator: Allocator, db: DB) !Self {
        const conn = try allocator.create(c.duckdb_connection);
        errdefer allocator.destroy(conn);

        if (api.duckdb_connect.?(db.ptr.*, conn) == DuckDBError) {
            return error.ConnectError;
        }

        return .{
            .allocator = allocator,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        const conn = self.conn;
        api.duckdb_disconnect.?(conn);
        self.allocator.destroy(conn);
        self.* = undefined;
    }
};

pub const Extension = struct {
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
    conn: Connection,

    const Self = @This();

    pub fn init(allocator: Allocator, info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Self {
        errdefer access.set_error.?(info, "Failed to initialize extension");

        try initAPI(info, access);

        const conn = try Connection.init(allocator, database);

        return .{
            .info = info,
            .access = access,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        self.conn.deinit();
        self.* = undefined;
    }

    // pub fn setError(self: Self, msg: [*:0]const u8) void {
    //     self.access.set_error.?(self.info, msg);
    // }

    pub fn getAPI(_: Self) *const duckdb_ext_api {
        return &api;
    }
};
