const std = @import("std");
pub const c = @import("duckdb_capi");

const Allocator = std.mem.Allocator;

const DuckDBError = c.DuckDBError;

const API = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const DB = struct {
    ptr: *c.duckdb_database,

    const Self = @This();

    pub fn provided(db: *c.duckdb_database) Self {
        return .{ .ptr = db };
    }
};

pub const Connection = struct {
    allocator: Allocator,
    api: API,
    conn: *c.duckdb_connection,

    const Self = @This();

    pub fn open(allocator: Allocator, db: DB, api: API) !Self {
        const conn = try allocator.create(c.duckdb_connection);
        errdefer allocator.destroy(conn);

        if (api.duckdb_connect.?(db.ptr.*, conn) == DuckDBError) {
            return error.ConnectError;
        }

        return .{
            .allocator = allocator,
            .conn = conn,
            .api = api,
        };
    }

    pub fn deinit(self: *Self) void {
        const conn = self.conn;
        self.api.duckdb_disconnect.?(conn);
        self.allocator.destroy(conn);
        self.* = undefined;
    }
};

pub const Extension = struct {
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
    db: DB,
    api: API,
    conn: Connection,

    const Self = @This();

    pub fn init(allocator: Allocator, info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Self {
        const db = DB.provided(access.get_database.?(info));
        const api = try getAPI(info, access);
        const conn = Connection.open(allocator, db, api) catch |e| {
            access.set_error.?(info, "Failed to open connection to database");
            return e;
        };

        return .{
            .info = info,
            .access = access,
            .db = db,
            .api = api,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Self) void {
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

    // pub fn setError(self: Self, msg: [*:0]const u8) void {
    //     self.access.set_error.?(self.info, msg);
    // }
};
