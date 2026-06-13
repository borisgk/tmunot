const std = @import("std");
const core = @import("core.zig");

pub const UserRecord = struct {
    username: []const u8,
    password_hash: []const u8,
    real_name: []const u8,
    is_admin: bool,
    avatar_ext: ?[]const u8,
};

var global_users_db: ?*core.sqlite3 = null;
var global_allocator: std.mem.Allocator = undefined;

pub fn initUsersDb(allocator: std.mem.Allocator, db_path: []const u8) !void {
    global_allocator = allocator;
    
    var temp_db: ?*core.sqlite3 = null;
    const rc = core.sqlite3_open_v2(
        db_path.ptr,
        &temp_db,
        core.SQLITE_OPEN_READWRITE | core.SQLITE_OPEN_CREATE | core.SQLITE_OPEN_FULLMUTEX,
        null,
    );

    if (rc != core.SQLITE_OK) {
        if (temp_db) |t| _ = core.sqlite3_close(t);
        return error.SqliteOpenFailed;
    }

    const db = temp_db.?;
    global_users_db = db;

    var err_msg: [*c]u8 = null;
    const wal_rc = core.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, &err_msg);
    if (wal_rc != core.SQLITE_OK) {
        std.debug.print("Failed to set WAL mode: {s}\n", .{err_msg});
        if (err_msg) |msg| core.sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| core.sqlite3_free(msg);

    const create_sql =
        \\CREATE TABLE IF NOT EXISTS users (
        \\    username TEXT PRIMARY KEY,
        \\    password_hash TEXT NOT NULL,
        \\    real_name TEXT NOT NULL,
        \\    is_admin INTEGER NOT NULL DEFAULT 0,
        \\    avatar_ext TEXT
        \\);
    ;

    const create_rc = core.sqlite3_exec(db, create_sql, null, null, &err_msg);
    if (create_rc != core.SQLITE_OK) {
        std.debug.print("Failed to run migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| core.sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| core.sqlite3_free(msg);
}

pub fn deinitUsersDb() void {
    if (global_users_db) |db| {
        _ = core.sqlite3_close(db);
        global_users_db = null;
    }
}

pub fn insertUser(username: []const u8, password_hash: []const u8, real_name: []const u8, is_admin: bool, avatar_ext: ?[]const u8) !void {
    const db = global_users_db orelse return error.DbNotInitialized;

    const sql = "INSERT INTO users (username, password_hash, real_name, is_admin, avatar_ext) VALUES (?, ?, ?, ?, ?)";
    var stmt: ?*core.sqlite3_stmt = null;
    
    if (core.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, password_hash.ptr, @intCast(password_hash.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 3, real_name.ptr, @intCast(real_name.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_int(stmt, 4, if (is_admin) 1 else 0);
    if (avatar_ext) |ext| {
        _ = core.sqlite3_bind_text(stmt, 5, ext.ptr, @intCast(ext.len), core.SQLITE_TRANSIENT);
    } else {
        _ = core.sqlite3_bind_null(stmt, 5);
    }

    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) {
        return error.SqliteStepFailed;
    }
}

pub fn updateUser(username: []const u8, password_hash: ?[]const u8, real_name: ?[]const u8, is_admin: ?bool, avatar_ext: ?[]const u8) !void {
    const db = global_users_db orelse return error.DbNotInitialized;

    // Use a simpler approach: get user, update fields, save back. Wait, let's just do dynamic SQL.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    
    var sql = std.ArrayList(u8).empty;
    try sql.appendSlice(alloc, "UPDATE users SET ");
    
    var fields = std.ArrayList([]const u8).empty;
    if (password_hash != null) try fields.append(alloc, "password_hash = ?");
    if (real_name != null) try fields.append(alloc, "real_name = ?");
    if (is_admin != null) try fields.append(alloc, "is_admin = ?");
    if (avatar_ext != null) try fields.append(alloc, "avatar_ext = ?");
    
    if (fields.items.len == 0) return; // Nothing to update
    
    for (fields.items, 0..) |f, i| {
        try sql.appendSlice(alloc, f);
        if (i < fields.items.len - 1) try sql.appendSlice(alloc, ", ");
    }
    try sql.appendSlice(alloc, " WHERE username = ?\x00");
    
    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql.items.ptr, @intCast(sql.items.len - 1), &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    var bind_idx: c_int = 1;
    if (password_hash) |hash| {
        _ = core.sqlite3_bind_text(stmt, bind_idx, hash.ptr, @intCast(hash.len), core.SQLITE_TRANSIENT);
        bind_idx += 1;
    }
    if (real_name) |rn| {
        _ = core.sqlite3_bind_text(stmt, bind_idx, rn.ptr, @intCast(rn.len), core.SQLITE_TRANSIENT);
        bind_idx += 1;
    }
    if (is_admin) |admin| {
        _ = core.sqlite3_bind_int(stmt, bind_idx, if (admin) 1 else 0);
        bind_idx += 1;
    }
    if (avatar_ext) |ext| {
        // if empty string, set to null
        if (ext.len == 0) {
            _ = core.sqlite3_bind_null(stmt, bind_idx);
        } else {
            _ = core.sqlite3_bind_text(stmt, bind_idx, ext.ptr, @intCast(ext.len), core.SQLITE_TRANSIENT);
        }
        bind_idx += 1;
    }
    
    _ = core.sqlite3_bind_text(stmt, bind_idx, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);
    
    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) {
        return error.SqliteStepFailed;
    }
}

pub fn deleteUser(username: []const u8) !void {
    const db = global_users_db orelse return error.DbNotInitialized;

    const sql = "DELETE FROM users WHERE username = ?";
    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) {
        return error.SqliteStepFailed;
    }
}

pub fn getUser(username: []const u8, allocator: std.mem.Allocator) !?UserRecord {
    const db = global_users_db orelse return error.DbNotInitialized;

    const sql = "SELECT username, password_hash, real_name, is_admin, avatar_ext FROM users WHERE username = ?";
    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) == core.SQLITE_ROW) {
        const u_ptr = core.sqlite3_column_text(stmt, 0);
        const p_ptr = core.sqlite3_column_text(stmt, 1);
        const r_ptr = core.sqlite3_column_text(stmt, 2);
        const a_val = core.sqlite3_column_int(stmt, 3);
        const ext_ptr = core.sqlite3_column_text(stmt, 4);

        const ext_str: ?[]const u8 = if (ext_ptr != null) 
            try allocator.dupe(u8, std.mem.span(ext_ptr)) 
        else 
            null;

        return UserRecord{
            .username = try allocator.dupe(u8, std.mem.span(u_ptr)),
            .password_hash = try allocator.dupe(u8, std.mem.span(p_ptr)),
            .real_name = try allocator.dupe(u8, std.mem.span(r_ptr)),
            .is_admin = a_val == 1,
            .avatar_ext = ext_str,
        };
    }

    return null;
}

pub fn getUsers(allocator: std.mem.Allocator) ![]UserRecord {
    const db = global_users_db orelse return error.DbNotInitialized;

    const sql = "SELECT username, password_hash, real_name, is_admin, avatar_ext FROM users";
    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    var list = std.ArrayList(UserRecord).empty;
    errdefer {
        for (list.items) |u| {
            allocator.free(u.username);
            allocator.free(u.password_hash);
            allocator.free(u.real_name);
            if (u.avatar_ext) |ext| allocator.free(ext);
        }
        list.deinit(allocator);
    }

    while (core.sqlite3_step(stmt) == core.SQLITE_ROW) {
        const u_ptr = core.sqlite3_column_text(stmt, 0);
        const p_ptr = core.sqlite3_column_text(stmt, 1);
        const r_ptr = core.sqlite3_column_text(stmt, 2);
        const a_val = core.sqlite3_column_int(stmt, 3);
        const ext_ptr = core.sqlite3_column_text(stmt, 4);

        const ext_str: ?[]const u8 = if (ext_ptr != null) 
            try allocator.dupe(u8, std.mem.span(ext_ptr)) 
        else 
            null;

        try list.append(allocator, .{
            .username = try allocator.dupe(u8, std.mem.span(u_ptr)),
            .password_hash = try allocator.dupe(u8, std.mem.span(p_ptr)),
            .real_name = try allocator.dupe(u8, std.mem.span(r_ptr)),
            .is_admin = a_val == 1,
            .avatar_ext = ext_str,
        });
    }

    return list.toOwnedSlice(allocator);
}
