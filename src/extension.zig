const std = @import("std");
pub const c = @import("duckdb_capi");

pub const Connection = struct {
    conn: *c.duckdb_connection,
    api: duckdb_ext_api,

    const Self = @This();

    pub fn open(db: c.duckdb_database, api: duckdb_ext_api) !Self {
        var conn: c.duckdb_connection = null;
        if (api.duckdb_connect.?(db, &conn) == c.DuckDBError) {
            return error.ConnectFailed;
        }
        return .{ .conn = &conn, .api = api };
    }

    pub fn deinit(self: *const Self) void {
        self.api.duckdb_disconnect.?(self.conn);
    }
};

const duckdb_ext_api = if (@hasDecl(c, "duckdb_ext_api_v0"))
    c.duckdb_ext_api_v0
else if (@hasDecl(c, "duckdb_ext_api_v1"))
    c.duckdb_ext_api_v1
else
    @compileError("unsupported DuckDB extension API version");

pub const Extension = struct {
    info: c.duckdb_extension_info,
    access: *c.duckdb_extension_access,
    db: c.duckdb_database,
    api: duckdb_ext_api,
    conn: ?Connection,

    const Self = @This();

    const min_api_version = std.fmt.comptimePrint("v{d}.{d}.{d}", .{
        c.DUCKDB_EXTENSION_API_VERSION_MAJOR,
        c.DUCKDB_EXTENSION_API_VERSION_MINOR,
        c.DUCKDB_EXTENSION_API_VERSION_PATCH,
    });

    pub fn init(info: c.duckdb_extension_info, access: *c.duckdb_extension_access) !Self {
        const db: c.duckdb_database = @ptrCast(access.get_database.?(info));

        const maybe_api: ?*const duckdb_ext_api = @ptrCast(@alignCast(access.get_api.?(info, min_api_version)));
        if (maybe_api == null) {
            return error.APIVersionNotSupported;
        }
        const api = maybe_api.?.*;

        const conn = try Connection.open(db, api);

        return .{
            .info = info,
            .access = access,
            .db = db,
            .api = api,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.conn) |conn| {
            conn.deinit();
        }
        self.* = undefined;
    }

    pub fn releaseConnection(self: *Extension) Connection {
        const connection = self.conn.?;
        self.conn = null;
        return connection;
    }

    pub fn set_error(self: Self, msg: [*:0]const u8) void {
        self.access.set_error.?(self.info, msg);
    }
};
