const std = @import("std");
const db = @import("../../db.zig");
const server = @import("../../server.zig");
const processor = @import("../../processor.zig");
const config_mod = @import("../../config.zig");

extern "c" fn time(t: ?*i64) i64;
pub fn handleCreateAlbum(req: *std.http.Server.Request, allocator: std.mem.Allocator, username: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body_str = try r.allocRemaining(allocator, .limited(4 * 1024));

    const CreateAlbumRequest = struct {
        name: []const u8,
        description: ?[]const u8 = null,
    };

    const parsed = std.json.parseFromSlice(
        CreateAlbumRequest,
        allocator,
        body_str,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        try req.respond("Invalid JSON", .{ .status = .bad_request });
        return;
    };
    defer parsed.deinit();

    if (parsed.value.name.len == 0) {
        try req.respond("Name is required", .{ .status = .bad_request });
        return;
    }

    var record: db.AlbumRecord = undefined;
    record.username = username;
    record.name = parsed.value.name;
    record.description = parsed.value.description;
    record.cover_photo_uuid = null;
    record.cover_photo_extension = null;
    record.photo_count = 0;
    
    // Generate UUID
    var uuid_buf: [36]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(time(null))));
    var rand = prng.random();
    const hex_charset = "0123456789abcdef";
    for (&uuid_buf, 0..) |*c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) {
            c.* = '-';
        } else if (i == 14) {
            c.* = '4';
        } else if (i == 19) {
            const char_idx = 8 + (rand.int(u8) % 4);
            c.* = hex_charset[char_idx];
        } else {
            c.* = hex_charset[rand.int(u8) % 16];
        }
    }
    record.uuid = &uuid_buf;
    
    const server_upload = @import("../upload.zig");
    const current_time = try server_upload.getCurrentDateTime(allocator);
    record.created_at = current_time.iso_str;
    record.updated_at = current_time.iso_str;

    db.insertAlbum(record) catch {
        try req.respond("Database Error", .{ .status = .internal_server_error });
        return;
    };

    try req.respond("Created", .{ .status = .created });
}
pub fn handleListAlbums(req: *std.http.Server.Request, allocator: std.mem.Allocator, username: []const u8) !void {
    const albums = try db.getAlbums(username, allocator);
    var aw: std.Io.Writer.Allocating = .init(allocator);
    try std.json.Stringify.value(albums, .{}, &aw.writer);
    try req.respond(aw.written(), .{
        .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
    });
}

pub fn handleAddPhotosToAlbum(req: *std.http.Server.Request, allocator: std.mem.Allocator, username: []const u8, album_uuid: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body_str = try r.allocRemaining(allocator, .limited(64 * 1024));

    const AddPhotosRequest = struct {
        photos: [][]const u8,
    };

    const parsed = std.json.parseFromSlice(
        AddPhotosRequest,
        allocator,
        body_str,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        try req.respond("Invalid JSON", .{ .status = .bad_request });
        return;
    };
    defer parsed.deinit();

    // Verify album exists and belongs to the user
    const album_record = try db.getAlbum(username, album_uuid, allocator);
    if (album_record == null) {
        try req.respond("Album Not Found", .{ .status = .not_found });
        return;
    }

    const current_time = try @import("../upload.zig").getCurrentDateTime(allocator);

    for (parsed.value.photos) |photo_uuid| {
        var record: db.AlbumPhotoRecord = undefined;
        record.album_uuid = album_uuid;
        record.photo_uuid = photo_uuid;
        record.added_at = current_time.iso_str;
        db.insertAlbumPhoto(username, record) catch |err| {
            std.debug.print("Failed to add photo {s} to album {s}: {}\n", .{ photo_uuid, album_uuid, err });
            try req.respond("{\"error\":\"Failed to add photos to album\"}", .{
                .status = .internal_server_error,
                .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
            });
            return;
        };
    }

    try req.respond("{\"status\":\"ok\"}", .{
        .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
    });
}

pub fn handleRemovePhotoFromAlbum(req: *std.http.Server.Request, allocator: std.mem.Allocator, username: []const u8, album_uuid: []const u8, photo_uuid: []const u8) !void {
    _ = allocator;
    db.deleteAlbumPhoto(username, album_uuid, photo_uuid) catch {
        try req.respond("Database Error", .{ .status = .internal_server_error });
        return;
    };

    try req.respond("{\"status\":\"ok\"}", .{
        .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
    });
}

