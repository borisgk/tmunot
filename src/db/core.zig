const std = @import("std");
const photos = @import("photos.zig");

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;
pub const SQLITE_NULL: c_int = 5;

pub const SQLITE_OPEN_READONLY: c_int = 0x00000001;
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

pub extern "c" fn sqlite3_busy_timeout(db: ?*sqlite3, ms: c_int) c_int;

pub var db_mutex = std.Io.Mutex.init;
pub var user_dbs: std.StringHashMap(*sqlite3) = undefined;
pub var global_io: ?std.Io = null;
pub var global_allocator: std.mem.Allocator = undefined;
pub var global_db_dir: []const u8 = undefined;

pub fn init(allocator: std.mem.Allocator, io: std.Io, db_dir: []const u8) !void {
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    if (global_io != null) return;
    global_io = io;
    global_allocator = allocator;
    global_db_dir = try allocator.dupe(u8, db_dir);
    user_dbs = std.StringHashMap(*sqlite3).init(allocator);

    std.Io.Dir.cwd().createDirPath(io, global_db_dir) catch {};
}

pub fn getUserVersion(db: ?*sqlite3) i32 {
    const sql = "PRAGMA user_version;";
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, @intCast(sql.len), &stmt, null) != SQLITE_OK) return 0;
    defer _ = sqlite3_finalize(stmt);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        return sqlite3_column_int(stmt, 0);
    }
    return 0;
}

pub fn setUserVersion(db: ?*sqlite3, version: i32) void {
    const sql = std.fmt.allocPrintSentinel(global_allocator, "PRAGMA user_version = {d};", .{version}, 0) catch return;
    defer global_allocator.free(sql);
    var err_msg: [*c]u8 = null;
    _ = sqlite3_exec(db, sql.ptr, null, null, &err_msg);
    if (err_msg) |msg| sqlite3_free(msg);
}

extern "c" fn time(t: ?*i64) i64;

fn backupDatabase(io: std.Io, path: []const u8) !void {
    const backup_path = try std.fmt.allocPrint(global_allocator, "{s}.{d}.bak", .{ path, time(null) });
    defer global_allocator.free(backup_path);

    const cwd = std.Io.Dir.cwd();
    var src_file = try cwd.openFile(io, path, .{});
    defer src_file.close(io);

    const size = (try src_file.stat(io)).size;
    const buffer = try global_allocator.alloc(u8, @intCast(size));
    defer global_allocator.free(buffer);

    var reader = src_file.reader(io, &.{});
    try reader.interface.readSliceAll(buffer);

    var dst_file = try cwd.createFile(io, backup_path, .{});
    defer dst_file.close(io);

    var writer = dst_file.writer(io, &.{});
    try writer.interface.writeAll(buffer);

    std.debug.print("Backup created: {s}\n", .{backup_path});
}

pub fn syncTableSchema(comptime T: type, db: ?*sqlite3, table_name: []const u8) !void {
    const field_names = comptime std.meta.fieldNames(T);
    
    const sql = try std.fmt.allocPrintSentinel(global_allocator, "PRAGMA table_info(\"{s}\");", .{table_name}, 0);
    defer global_allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = sqlite3_finalize(stmt);

    var existing_cols = std.StringHashMap(void).init(global_allocator);
    defer existing_cols.deinit();

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const col_name_c = sqlite3_column_text(stmt, 1);
        const col_name = std.mem.span(col_name_c);
        try existing_cols.put(try global_allocator.dupe(u8, col_name), {});
    }
    
    // Check for missing columns
    inline for (field_names) |field_name| {
        if (!existing_cols.contains(field_name)) {
            std.debug.print("Sync: Adding missing column '{s}' to table '{s}'\n", .{ field_name, table_name });
            const alter_sql = try std.fmt.allocPrintSentinel(global_allocator, "ALTER TABLE \"{s}\" ADD COLUMN \"{s}\" TEXT;", .{ table_name, field_name }, 0);
            defer global_allocator.free(alter_sql);
            
            var err_msg: [*c]u8 = null;
            const alter_rc = sqlite3_exec(db, alter_sql.ptr, null, null, &err_msg);
            if (alter_rc != SQLITE_OK) {
                std.debug.print("Failed to add column: {s}\n", .{err_msg});
                if (err_msg) |msg| sqlite3_free(msg);
                return error.SqliteExecFailed;
            }
            if (err_msg) |msg| sqlite3_free(msg);
        }
    }

    // Cleanup keys
    var it = existing_cols.keyIterator();
    while (it.next()) |key| {
        global_allocator.free(key.*);
    }
}

pub fn getDb(username: []const u8) !*sqlite3 {
    const io = global_io orelse return error.NoGlobalIo;
    if (user_dbs.get(username)) |db| {
        return db;
    }

    const db_path = try std.fmt.allocPrint(global_allocator, "{s}/{s}.db", .{ global_db_dir, username });
    defer global_allocator.free(db_path);
    const db_path_c = try std.fmt.allocPrintSentinel(global_allocator, "{s}", .{db_path}, 0);
    defer global_allocator.free(db_path_c);

    const file_exists = blk: {
        const cwd = std.Io.Dir.cwd();
        var f = cwd.openFile(io, db_path, .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        f.close(io);
        break :blk true;
    };

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

    const db = temp_db.?;

    const current_version = getUserVersion(db);
    const target_version: i32 = 1;

    if (file_exists and current_version < target_version) {
        try backupDatabase(io, db_path);
    }

    var err_msg: [*c]u8 = null;
    const wal_rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, &err_msg);
    if (wal_rc != SQLITE_OK) {
        std.debug.print("Failed to set WAL mode: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

    const fk_rc = sqlite3_exec(db, "PRAGMA foreign_keys=ON;", null, null, &err_msg);
    if (fk_rc != SQLITE_OK) {
        std.debug.print("Failed to set foreign keys: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

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
        \\CREATE TABLE IF NOT EXISTS albums (
        \\    uuid TEXT PRIMARY KEY,
        \\    username TEXT NOT NULL,
        \\    name TEXT NOT NULL,
        \\    description TEXT,
        \\    cover_photo_uuid TEXT REFERENCES photos(uuid) ON DELETE SET NULL,
        \\    created_at TEXT NOT NULL,
        \\    updated_at TEXT NOT NULL
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_albums_username ON albums(username);
        \\CREATE TABLE IF NOT EXISTS album_photos (
        \\    album_uuid TEXT NOT NULL REFERENCES albums(uuid) ON DELETE CASCADE,
        \\    photo_uuid TEXT NOT NULL REFERENCES photos(uuid) ON DELETE CASCADE,
        \\    added_at TEXT NOT NULL,
        \\    PRIMARY KEY (album_uuid, photo_uuid)
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_album_photos_photo ON album_photos(photo_uuid);
    ;

    const create_exif_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var sql: []const u8 = "CREATE TABLE IF NOT EXISTS photo_exif (uuid TEXT PRIMARY KEY REFERENCES photos(uuid) ON DELETE CASCADE";
        for (std.meta.fieldNames(photos.PhotoExifRecord)) |field_name| {
            if (std.mem.eql(u8, field_name, "uuid")) continue;
            sql = sql ++ ", \"" ++ field_name ++ "\" TEXT";
        }
        sql = sql ++ ");\nCREATE INDEX IF NOT EXISTS idx_photo_exif_make ON photo_exif(\"Make\");\nCREATE INDEX IF NOT EXISTS idx_photo_exif_model ON photo_exif(\"Model\");\x00";
        break :blk sql;
    };

    const create_video_meta_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var sql: []const u8 = "CREATE TABLE IF NOT EXISTS video_metadata (uuid TEXT PRIMARY KEY REFERENCES photos(uuid) ON DELETE CASCADE";
        for (std.meta.fieldNames(photos.VideoMetadataRecord)) |field_name| {
            if (std.mem.eql(u8, field_name, "uuid")) continue;
            sql = sql ++ ", \"" ++ field_name ++ "\" TEXT";
        }
        sql = sql ++ ");\x00";
        break :blk sql;
    };

    const create_rc = sqlite3_exec(db, create_sql, null, null, &err_msg);
    if (create_rc != SQLITE_OK) {
        std.debug.print("Failed to run migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

    const create_exif_rc = sqlite3_exec(db, create_exif_sql.ptr, null, null, &err_msg);
    if (create_exif_rc != SQLITE_OK) {
        std.debug.print("Failed to run exif migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

    const create_video_meta_rc = sqlite3_exec(db, create_video_meta_sql.ptr, null, null, &err_msg);
    if (create_video_meta_rc != SQLITE_OK) {
        std.debug.print("Failed to run video meta migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

    // Automatically sync dynamic tables
    try syncTableSchema(photos.PhotoExifRecord, db, "photo_exif");
    try syncTableSchema(photos.VideoMetadataRecord, db, "video_metadata");

    // After all migrations are successful, set the version
    if (current_version < target_version) {
        setUserVersion(db, target_version);
    }

    const username_dup = try global_allocator.dupe(u8, username);
    try user_dbs.put(username_dup, db);

    return db;
}

pub fn deinit() void {
    if (global_io) |io| {
        db_mutex.lockUncancelable(io);
        defer db_mutex.unlock(io);

        var it = user_dbs.iterator();
        while (it.next()) |entry| {
            _ = sqlite3_close(entry.value_ptr.*);
            global_allocator.free(entry.key_ptr.*);
        }
        user_dbs.deinit();
        global_allocator.free(global_db_dir);
    }
}
