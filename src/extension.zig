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

pub const DB = struct {
    ptr: *c.duckdb_database,

    const Self = @This();

    pub fn provided(db: *c.duckdb_database) Self {
        return .{ .ptr = db };
    }
};

pub const Connection = struct {
    allocator: Allocator,
    api: duckdb_ext_api,
    conn: *c.duckdb_connection,

    const Self = @This();

    pub fn init(allocator: Allocator, db: DB, api: duckdb_ext_api) !Self {
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
    api: duckdb_ext_api,
    conn: Connection,

    const Self = @This();

    const min_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
        c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
        c.DUCKDB_EXTENSION_API_VERSION_MINOR,
        c.DUCKDB_EXTENSION_API_VERSION_PATCH,
    });

    pub fn init(allocator: Allocator, info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Self {
        const db = DB.provided(access.get_database.?(info));

        const maybe_api: ?*const duckdb_ext_api = @ptrCast(@alignCast(access.get_api.?(info, min_api_version)));
        if (maybe_api == null) {
            return error.APIVersionNotSupported;
        }
        const api = maybe_api.?.*;

        const conn = try Connection.init(allocator, db, api);

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

    // pub fn setError(self: Self, msg: [*:0]const u8) void {
    //     self.access.set_error.?(self.info, msg);
    // }
};
