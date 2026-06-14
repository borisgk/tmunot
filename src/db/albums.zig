const std = @import("std");
const core = @import("core.zig");
const photos = @import("photos.zig");

pub const AlbumRecord = struct {
    uuid: []const u8,
    username: []const u8,
    name: []const u8,
    description: ?[]const u8,
    cover_photo_uuid: ?[]const u8,
    cover_photo_extension: ?[]const u8,
    photo_count: i32,
    created_at: []const u8,
    updated_at: []const u8,
};

pub const AlbumPhotoRecord = struct {
    album_uuid: []const u8,
    photo_uuid: []const u8,
    added_at: []const u8,
};
pub fn insertAlbum(record: AlbumRecord) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(record.username);

    const insert_sql =
        \\INSERT INTO albums (uuid, username, name, description, cover_photo_uuid, created_at, updated_at)
        \\VALUES (?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, record.username.ptr, @intCast(record.username.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 3, record.name.ptr, @intCast(record.name.len), core.SQLITE_TRANSIENT);
    if (record.description) |desc| {
        _ = core.sqlite3_bind_text(stmt, 4, desc.ptr, @intCast(desc.len), core.SQLITE_TRANSIENT);
    } else {
        _ = core.sqlite3_bind_null(stmt, 4);
    }
    if (record.cover_photo_uuid) |cover| {
        _ = core.sqlite3_bind_text(stmt, 5, cover.ptr, @intCast(cover.len), core.SQLITE_TRANSIENT);
    } else {
        _ = core.sqlite3_bind_null(stmt, 5);
    }
    _ = core.sqlite3_bind_text(stmt, 6, record.created_at.ptr, @intCast(record.created_at.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 7, record.updated_at.ptr, @intCast(record.updated_at.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to insert album: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn updateAlbumCover(username: []const u8, album_uuid: []const u8, cover_photo_uuid: []const u8) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = "UPDATE albums SET cover_photo_uuid = ? WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, cover_photo_uuid.ptr, @intCast(cover_photo_uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, album_uuid.ptr, @intCast(album_uuid.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) return error.SqliteUpdateFailed;
}

pub fn insertAlbumPhoto(username: []const u8, record: AlbumPhotoRecord) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const insert_sql =
        \\INSERT INTO album_photos (album_uuid, photo_uuid, added_at)
        \\VALUES (?, ?, ?) ON CONFLICT DO NOTHING;
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    const prep_rc = core.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null);
    if (prep_rc != core.SQLITE_OK) {
        std.debug.print("[ALBUM-DB] ERROR: sqlite3_prepare_v2 failed for insertAlbumPhoto (photo: {s}): code {d}, msg: {s}\n", .{ record.photo_uuid, prep_rc, core.sqlite3_errmsg(db) });
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, record.album_uuid.ptr, @intCast(record.album_uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, record.photo_uuid.ptr, @intCast(record.photo_uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 3, record.added_at.ptr, @intCast(record.added_at.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("[ALBUM-DB] ERROR: sqlite3_step failed for insertAlbumPhoto (photo: {s}): code {d}, msg: {s}\n", .{ record.photo_uuid, rc, core.sqlite3_errmsg(db) });
        return error.SqliteInsertFailed;
    }
    
    // Auto-set cover photo if it's the first photo
    const check_sql = "SELECT cover_photo_uuid FROM albums WHERE uuid = ?;";
    var check_stmt: ?*core.sqlite3_stmt = null;
    const check_prep_rc = core.sqlite3_prepare_v2(db, check_sql, -1, &check_stmt, null);
    if (check_prep_rc == core.SQLITE_OK) {
        defer _ = core.sqlite3_finalize(check_stmt);
        _ = core.sqlite3_bind_text(check_stmt, 1, record.album_uuid.ptr, @intCast(record.album_uuid.len), core.SQLITE_TRANSIENT);
        const check_step_rc = core.sqlite3_step(check_stmt);
        if (check_step_rc == core.SQLITE_ROW) {
            if (core.sqlite3_column_type(check_stmt, 0) == core.SQLITE_NULL) {
                const update_sql = "UPDATE albums SET cover_photo_uuid = ? WHERE uuid = ?;";
                var update_stmt: ?*core.sqlite3_stmt = null;
                const update_prep_rc = core.sqlite3_prepare_v2(db, update_sql, -1, &update_stmt, null);
                if (update_prep_rc == core.SQLITE_OK) {
                    defer _ = core.sqlite3_finalize(update_stmt);
                    _ = core.sqlite3_bind_text(update_stmt, 1, record.photo_uuid.ptr, @intCast(record.photo_uuid.len), core.SQLITE_TRANSIENT);
                    _ = core.sqlite3_bind_text(update_stmt, 2, record.album_uuid.ptr, @intCast(record.album_uuid.len), core.SQLITE_TRANSIENT);
                    const update_step_rc = core.sqlite3_step(update_stmt);
                    if (update_step_rc != core.SQLITE_DONE) {
                        std.debug.print("[ALBUM-DB] WARNING: Auto-cover UPDATE failed for album '{s}': code {d}, msg: {s}\n", .{ record.album_uuid, update_step_rc, core.sqlite3_errmsg(db) });
                    }
                } else {
                    std.debug.print("[ALBUM-DB] WARNING: Auto-cover UPDATE prepare failed for album '{s}': code {d}, msg: {s}\n", .{ record.album_uuid, update_prep_rc, core.sqlite3_errmsg(db) });
                }
            }
        } else if (check_step_rc != core.SQLITE_DONE) {
            std.debug.print("[ALBUM-DB] WARNING: Auto-cover SELECT step failed for album '{s}': code {d}, msg: {s}\n", .{ record.album_uuid, check_step_rc, core.sqlite3_errmsg(db) });
        }
    } else {
        std.debug.print("[ALBUM-DB] WARNING: Auto-cover SELECT prepare failed for album '{s}': code {d}, msg: {s}\n", .{ record.album_uuid, check_prep_rc, core.sqlite3_errmsg(db) });
    }
}

pub fn getAlbums(username: []const u8, allocator: std.mem.Allocator) ![]AlbumRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql =
        \\SELECT 
        \\    a.uuid, 
        \\    a.username, 
        \\    a.name, 
        \\    a.description, 
        \\    a.cover_photo_uuid, 
        \\    p.extension,
        \\    (SELECT COUNT(*) FROM album_photos ap WHERE ap.album_uuid = a.uuid) AS photo_count,
        \\    a.created_at, 
        \\    a.updated_at
        \\FROM albums a
        \\LEFT JOIN photos p ON a.cover_photo_uuid = p.uuid
        \\WHERE a.username = ?
        \\ORDER BY a.created_at DESC;
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);

    var list = std.ArrayList(AlbumRecord).empty;
    errdefer {
        for (list.items) |r| {
            allocator.free(r.uuid);
            allocator.free(r.username);
            allocator.free(r.name);
            if (r.description) |desc| allocator.free(desc);
            if (r.cover_photo_uuid) |cover| allocator.free(cover);
            if (r.cover_photo_extension) |ext| allocator.free(ext);
            allocator.free(r.created_at);
            allocator.free(r.updated_at);
        }
        list.deinit(allocator);
    }

    while (true) {
        const rc = core.sqlite3_step(stmt);
        if (rc == core.SQLITE_ROW) {
            const desc_c = core.sqlite3_column_text(stmt, 3);
            const cover_c = core.sqlite3_column_text(stmt, 4);
            const ext_c = core.sqlite3_column_text(stmt, 5);

            const desc_len = core.sqlite3_column_bytes(stmt, 3);
            const cover_len = core.sqlite3_column_bytes(stmt, 4);
            const ext_len = core.sqlite3_column_bytes(stmt, 5);

            try list.append(allocator, AlbumRecord{
                .uuid = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 0)[0..@intCast(core.sqlite3_column_bytes(stmt, 0))]),
                .username = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 1)[0..@intCast(core.sqlite3_column_bytes(stmt, 1))]),
                .name = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 2)[0..@intCast(core.sqlite3_column_bytes(stmt, 2))]),
                .description = if (desc_c != null) try allocator.dupe(u8, desc_c[0..@intCast(desc_len)]) else null,
                .cover_photo_uuid = if (cover_c != null) try allocator.dupe(u8, cover_c[0..@intCast(cover_len)]) else null,
                .cover_photo_extension = if (ext_c != null) try allocator.dupe(u8, ext_c[0..@intCast(ext_len)]) else null,
                .photo_count = core.sqlite3_column_int(stmt, 6),
                .created_at = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 7)[0..@intCast(core.sqlite3_column_bytes(stmt, 7))]),
                .updated_at = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 8)[0..@intCast(core.sqlite3_column_bytes(stmt, 8))]),
            });
        } else if (rc == core.SQLITE_DONE) {
            break;
        } else {
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn getAlbum(username: []const u8, album_uuid: []const u8, allocator: std.mem.Allocator) !?AlbumRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql =
        \\SELECT 
        \\    a.uuid, 
        \\    a.username, 
        \\    a.name, 
        \\    a.description, 
        \\    a.cover_photo_uuid, 
        \\    p.extension,
        \\    (SELECT COUNT(*) FROM album_photos ap WHERE ap.album_uuid = a.uuid) AS photo_count,
        \\    a.created_at, 
        \\    a.updated_at
        \\FROM albums a
        \\LEFT JOIN photos p ON a.cover_photo_uuid = p.uuid
        \\WHERE a.username = ? AND a.uuid = ?;
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    const prep_rc = core.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (prep_rc != core.SQLITE_OK) {
        std.debug.print("[ALBUM-DB] ERROR: sqlite3_prepare_v2 failed in getAlbum (album: {s}): code {d}, msg: {s}\n", .{ album_uuid, prep_rc, core.sqlite3_errmsg(db) });
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, album_uuid.ptr, @intCast(album_uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc == core.SQLITE_ROW) {
        const desc_c = core.sqlite3_column_text(stmt, 3);
        const cover_c = core.sqlite3_column_text(stmt, 4);
        const ext_c = core.sqlite3_column_text(stmt, 5);

        const desc_len = core.sqlite3_column_bytes(stmt, 3);
        const cover_len = core.sqlite3_column_bytes(stmt, 4);
        const ext_len = core.sqlite3_column_bytes(stmt, 5);

        return AlbumRecord{
            .uuid = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 0)[0..@intCast(core.sqlite3_column_bytes(stmt, 0))]),
            .username = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 1)[0..@intCast(core.sqlite3_column_bytes(stmt, 1))]),
            .name = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 2)[0..@intCast(core.sqlite3_column_bytes(stmt, 2))]),
            .description = if (desc_c != null) try allocator.dupe(u8, desc_c[0..@intCast(desc_len)]) else null,
            .cover_photo_uuid = if (cover_c != null) try allocator.dupe(u8, cover_c[0..@intCast(cover_len)]) else null,
            .cover_photo_extension = if (ext_c != null) try allocator.dupe(u8, ext_c[0..@intCast(ext_len)]) else null,
            .photo_count = core.sqlite3_column_int(stmt, 6),
            .created_at = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 7)[0..@intCast(core.sqlite3_column_bytes(stmt, 7))]),
            .updated_at = try allocator.dupe(u8, core.sqlite3_column_text(stmt, 8)[0..@intCast(core.sqlite3_column_bytes(stmt, 8))]),
        };
    } else if (rc == core.SQLITE_DONE) {
        return null;
    } else {
        std.debug.print("[ALBUM-DB] ERROR: sqlite3_step failed in getAlbum (album: {s}): code {d}, msg: {s}\n", .{ album_uuid, rc, core.sqlite3_errmsg(db) });
        return error.SqliteSelectFailed;
    }
}

pub fn getAlbumPhotos(username: []const u8, album_uuid: []const u8, allocator: std.mem.Allocator) ![]photos.PhotoRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = 
        \\SELECT p.uuid, p.username, p.filename, p.extension, p.year, p.month, p.day, p.shooting_date, p.upload_date, p.width, p.height 
        \\FROM photos p
        \\JOIN album_photos ap ON p.uuid = ap.photo_uuid
        \\WHERE ap.album_uuid = ?
        \\ORDER BY COALESCE(p.shooting_date, p.upload_date) ASC, p.upload_date ASC;
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, album_uuid.ptr, @intCast(album_uuid.len), core.SQLITE_TRANSIENT);

    var list = std.ArrayList(photos.PhotoRecord).empty;
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
        const rc = core.sqlite3_step(stmt);
        if (rc == core.SQLITE_ROW) {
            const uuid_c = core.sqlite3_column_text(stmt, 0);
            const username_c = core.sqlite3_column_text(stmt, 1);
            const filename_c = core.sqlite3_column_text(stmt, 2);
            const extension_c = core.sqlite3_column_text(stmt, 3);
            const year_c = core.sqlite3_column_text(stmt, 4);
            const month_c = core.sqlite3_column_text(stmt, 5);
            const day_c = core.sqlite3_column_text(stmt, 6);
            const shooting_c = core.sqlite3_column_text(stmt, 7);
            const upload_c = core.sqlite3_column_text(stmt, 8);

            const is_null_width = core.sqlite3_column_type(stmt, 9) == core.SQLITE_NULL;
            const width: ?i32 = if (is_null_width) null else core.sqlite3_column_int(stmt, 9);

            const is_null_height = core.sqlite3_column_type(stmt, 10) == core.SQLITE_NULL;
            const height: ?i32 = if (is_null_height) null else core.sqlite3_column_int(stmt, 10);

            try list.append(allocator, photos.PhotoRecord{
                .uuid = try allocator.dupe(u8, uuid_c[0..@intCast(core.sqlite3_column_bytes(stmt, 0))]),
                .username = try allocator.dupe(u8, username_c[0..@intCast(core.sqlite3_column_bytes(stmt, 1))]),
                .filename = try allocator.dupe(u8, filename_c[0..@intCast(core.sqlite3_column_bytes(stmt, 2))]),
                .extension = try allocator.dupe(u8, extension_c[0..@intCast(core.sqlite3_column_bytes(stmt, 3))]),
                .year = try allocator.dupe(u8, year_c[0..@intCast(core.sqlite3_column_bytes(stmt, 4))]),
                .month = try allocator.dupe(u8, month_c[0..@intCast(core.sqlite3_column_bytes(stmt, 5))]),
                .day = try allocator.dupe(u8, day_c[0..@intCast(core.sqlite3_column_bytes(stmt, 6))]),
                .shooting_date = if (shooting_c != null) try allocator.dupe(u8, shooting_c[0..@intCast(core.sqlite3_column_bytes(stmt, 7))]) else null,
                .upload_date = try allocator.dupe(u8, upload_c[0..@intCast(core.sqlite3_column_bytes(stmt, 8))]),
                .width = width,
                .height = height,
            });
        } else if (rc == core.SQLITE_DONE) {
            break;
        } else {
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn deleteAlbum(username: []const u8, album_uuid: []const u8) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const delete_sql = "DELETE FROM albums WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, delete_sql, -1, &stmt, null) != core.SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, album_uuid.ptr, @intCast(album_uuid.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) return error.SqliteDeleteFailed;
}

pub fn deleteAlbumPhoto(username: []const u8, album_uuid: []const u8, photo_uuid: []const u8) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const delete_sql = "DELETE FROM album_photos WHERE album_uuid = ? AND photo_uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, delete_sql, -1, &stmt, null) != core.SQLITE_OK) return error.SqlitePrepareFailed;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, album_uuid.ptr, @intCast(album_uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, photo_uuid.ptr, @intCast(photo_uuid.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) != core.SQLITE_DONE) return error.SqliteDeleteFailed;
}
