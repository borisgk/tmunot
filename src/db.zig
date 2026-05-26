const std = @import("std");

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;
pub const SQLITE_NULL: c_int = 5;

pub const SQLITE_OPEN_READWRITE: c_int = 0x00000002;
pub const SQLITE_OPEN_CREATE: c_int = 0x00000004;
pub const SQLITE_OPEN_FULLMUTEX: c_int = 0x00010000;

pub const SQLITE_TRANSIENT = @as(?*anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))));

pub extern "c" fn sqlite3_open_v2(
    filename: [*c]const u8,
    ppDb: *?*sqlite3,
    flags: c_int,
    zVfs: [*c]const u8,
) c_int;

pub extern "c" fn sqlite3_close(db: ?*sqlite3) c_int;

pub extern "c" fn sqlite3_exec(
    db: ?*sqlite3,
    sql: [*c]const u8,
    callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int,
    arg: ?*anyopaque,
    errmsg: *[*c]u8,
) c_int;

pub extern "c" fn sqlite3_free(ptr: ?*anyopaque) void;

pub extern "c" fn sqlite3_prepare_v2(
    db: ?*sqlite3,
    zSql: [*c]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: ?*[*c]const u8,
) c_int;

pub extern "c" fn sqlite3_finalize(pStmt: ?*sqlite3_stmt) c_int;

pub extern "c" fn sqlite3_step(pStmt: ?*sqlite3_stmt) c_int;

pub extern "c" fn sqlite3_errmsg(db: ?*sqlite3) [*c]const u8;

pub extern "c" fn sqlite3_bind_text(
    pStmt: ?*sqlite3_stmt,
    idx: c_int,
    value: [*c]const u8,
    nBytes: c_int,
    destructor: ?*anyopaque,
) c_int;

pub extern "c" fn sqlite3_bind_null(pStmt: ?*sqlite3_stmt, idx: c_int) c_int;

pub extern "c" fn sqlite3_bind_int(pStmt: ?*sqlite3_stmt, idx: c_int, value: c_int) c_int;

pub extern "c" fn sqlite3_column_text(pStmt: ?*sqlite3_stmt, iCol: c_int) [*c]const u8;

pub extern "c" fn sqlite3_column_bytes(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub extern "c" fn sqlite3_column_int(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub extern "c" fn sqlite3_column_type(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub const PhotoRecord = struct {
    uuid: []const u8,
    username: []const u8,
    filename: []const u8,
    extension: []const u8,
    year: []const u8,
    month: []const u8,
    day: []const u8,
    shooting_date: ?[]const u8,
    upload_date: []const u8,
    width: ?i32,
    height: ?i32,
};

pub const LocationRecord = struct {
    username: []const u8,
    year: []const u8,
    month: []const u8,
    extension: []const u8,
};

var db_mutex = std.Io.Mutex.init;
var db_conn: ?*sqlite3 = null;
var global_io: ?std.Io = null;

pub fn init(allocator: std.mem.Allocator, io: std.Io, db_path: []const u8) !void {
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    if (db_conn != null) return;
    global_io = io;

    const db_path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{db_path}, 0);
    defer allocator.free(db_path_c);

    var temp_db: ?*sqlite3 = null;
    const rc = sqlite3_open_v2(
        db_path_c,
        &temp_db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        null,
    );

    if (rc != SQLITE_OK) {
        if (temp_db) |t| _ = sqlite3_close(t);
        return error.SqliteOpenFailed;
    }
    db_conn = temp_db;

    // Set WAL mode - REQUIRED by the user "always be using sqlite WAL"
    var err_msg: [*c]u8 = null;
    const wal_rc = sqlite3_exec(db_conn, "PRAGMA journal_mode=WAL;", null, null, &err_msg);
    if (wal_rc != SQLITE_OK) {
        std.debug.print("Failed to set WAL mode: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);
    std.debug.print("SQLite WAL mode initialized successfully.\n", .{});

    // Create table and indices
    const create_sql =
        \\CREATE TABLE IF NOT EXISTS photos (
        \\    uuid TEXT PRIMARY KEY,
        \\    username TEXT NOT NULL,
        \\    filename TEXT NOT NULL,
        \\    extension TEXT NOT NULL,
        \\    year TEXT NOT NULL,
        \\    month TEXT NOT NULL,
        \\    day TEXT NOT NULL,
        \\    shooting_date TEXT,
        \\    upload_date TEXT NOT NULL,
        \\    width INTEGER,
        \\    height INTEGER
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_photos_username ON photos(username);
        \\CREATE INDEX IF NOT EXISTS idx_photos_shooting_upload ON photos(shooting_date, upload_date);
    ;

    const create_rc = sqlite3_exec(db_conn, create_sql, null, null, &err_msg);
    if (create_rc != SQLITE_OK) {
        std.debug.print("Failed to run migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);
}

pub fn deinit() void {
    if (global_io) |io| {
        db_mutex.lockUncancelable(io);
        defer db_mutex.unlock(io);

        if (db_conn) |db| {
            _ = sqlite3_close(db);
            db_conn = null;
        }
    }
}

pub fn insertPhoto(record: PhotoRecord) !void {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const insert_sql =
        \\INSERT INTO photos (uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    // Bind parameters
    _ = sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 2, record.username.ptr, @intCast(record.username.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 3, record.filename.ptr, @intCast(record.filename.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 4, record.extension.ptr, @intCast(record.extension.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 5, record.year.ptr, @intCast(record.year.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 6, record.month.ptr, @intCast(record.month.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 7, record.day.ptr, @intCast(record.day.len), SQLITE_TRANSIENT);

    if (record.shooting_date) |sd| {
        _ = sqlite3_bind_text(stmt, 8, sd.ptr, @intCast(sd.len), SQLITE_TRANSIENT);
    } else {
        _ = sqlite3_bind_null(stmt, 8);
    }

    _ = sqlite3_bind_text(stmt, 9, record.upload_date.ptr, @intCast(record.upload_date.len), SQLITE_TRANSIENT);

    if (record.width) |w| {
        _ = sqlite3_bind_int(stmt, 10, w);
    } else {
        _ = sqlite3_bind_null(stmt, 10);
    }

    if (record.height) |h| {
        _ = sqlite3_bind_int(stmt, 11, h);
    } else {
        _ = sqlite3_bind_null(stmt, 11);
    }

    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std.debug.print("Failed to insert photo: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn updatePhotoDimensions(uuid: []const u8, width: i32, height: i32) !void {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const sql = "UPDATE photos SET width = ?, height = ? WHERE uuid = ?;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_int(stmt, 1, width);
    _ = sqlite3_bind_int(stmt, 2, height);
    _ = sqlite3_bind_text(stmt, 3, uuid.ptr, @intCast(uuid.len), SQLITE_TRANSIENT);

    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std.debug.print("Failed to update photo dimensions: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteUpdateFailed;
    }
}

pub fn getPhotoLocation(uuid: []const u8, allocator: std.mem.Allocator) !?LocationRecord {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const sql = "SELECT username, year, month, extension FROM photos WHERE uuid = ?;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), SQLITE_TRANSIENT);

    const rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const username_c = sqlite3_column_text(stmt, 0);
        const year_c = sqlite3_column_text(stmt, 1);
        const month_c = sqlite3_column_text(stmt, 2);
        const extension_c = sqlite3_column_text(stmt, 3);

        const username_len = sqlite3_column_bytes(stmt, 0);
        const year_len = sqlite3_column_bytes(stmt, 1);
        const month_len = sqlite3_column_bytes(stmt, 2);
        const extension_len = sqlite3_column_bytes(stmt, 3);

        return LocationRecord{
            .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
            .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
            .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
            .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
        };
    } else if (rc == SQLITE_DONE) {
        return null;
    } else {
        std.debug.print("Failed to get photo location: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteSelectFailed;
    }
}

pub fn getUserPhotos(username: []const u8, allocator: std.mem.Allocator) ![]PhotoRecord {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const sql = "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), SQLITE_TRANSIENT);

    var list = std.ArrayList(PhotoRecord).empty;
    errdefer {
        for (list.items) |r| {
            allocator.free(r.uuid);
            allocator.free(r.username);
            allocator.free(r.filename);
            allocator.free(r.extension);
            allocator.free(r.year);
            allocator.free(r.month);
            allocator.free(r.day);
            if (r.shooting_date) |sd| allocator.free(sd);
            allocator.free(r.upload_date);
        }
        list.deinit(allocator);
    }

    while (true) {
        const rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            const uuid_c = sqlite3_column_text(stmt, 0);
            const username_c = sqlite3_column_text(stmt, 1);
            const filename_c = sqlite3_column_text(stmt, 2);
            const extension_c = sqlite3_column_text(stmt, 3);
            const year_c = sqlite3_column_text(stmt, 4);
            const month_c = sqlite3_column_text(stmt, 5);
            const day_c = sqlite3_column_text(stmt, 6);
            const shooting_c = sqlite3_column_text(stmt, 7);
            const upload_c = sqlite3_column_text(stmt, 8);

            const uuid_len = sqlite3_column_bytes(stmt, 0);
            const username_len = sqlite3_column_bytes(stmt, 1);
            const filename_len = sqlite3_column_bytes(stmt, 2);
            const extension_len = sqlite3_column_bytes(stmt, 3);
            const year_len = sqlite3_column_bytes(stmt, 4);
            const month_len = sqlite3_column_bytes(stmt, 5);
            const day_len = sqlite3_column_bytes(stmt, 6);
            const shooting_len = sqlite3_column_bytes(stmt, 7);
            const upload_len = sqlite3_column_bytes(stmt, 8);

            const is_null_width = sqlite3_column_type(stmt, 9) == SQLITE_NULL;
            const width: ?i32 = if (is_null_width) null else sqlite3_column_int(stmt, 9);

            const is_null_height = sqlite3_column_type(stmt, 10) == SQLITE_NULL;
            const height: ?i32 = if (is_null_height) null else sqlite3_column_int(stmt, 10);

            const shooting_date = if (shooting_c != null) try allocator.dupe(u8, shooting_c[0..@intCast(shooting_len)]) else null;

            try list.append(allocator, PhotoRecord{
                .uuid = try allocator.dupe(u8, uuid_c[0..@intCast(uuid_len)]),
                .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
                .filename = try allocator.dupe(u8, filename_c[0..@intCast(filename_len)]),
                .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
                .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
                .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
                .day = try allocator.dupe(u8, day_c[0..@intCast(day_len)]),
                .shooting_date = shooting_date,
                .upload_date = try allocator.dupe(u8, upload_c[0..@intCast(upload_len)]),
                .width = width,
                .height = height,
            });
        } else if (rc == SQLITE_DONE) {
            break;
        } else {
            std.debug.print("Failed to step getUserPhotos: {s}\n", .{sqlite3_errmsg(db)});
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}
