const std = @import("std");
const db = @import("../db.zig");
const server = @import("../server.zig");
const config_mod = @import("../config.zig");
const exif_mod = @import("../exif.zig");
const video_meta_mod = @import("../video_meta.zig");

pub fn handleGetMetadata(req: *std.http.Server.Request, req_alloc: std.mem.Allocator, username: []const u8, target: []const u8) !void {
    const photo_uuid = target[12 .. target.len - 9];
    if (photo_uuid.len == 36) {
        if (try db.getPhotoExif(username, photo_uuid, req_alloc)) |exif| {
            var aw: std.Io.Writer.Allocating = .init(req_alloc);
            try std.json.Stringify.value(exif, .{}, &aw.writer);
            try req.respond(aw.written(), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                },
            });
            return;
        } else if (try db.getVideoMetadata(username, photo_uuid, req_alloc)) |video_meta| {
            var aw: std.Io.Writer.Allocating = .init(req_alloc);
            try std.json.Stringify.value(video_meta, .{}, &aw.writer);
            try req.respond(aw.written(), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                },
            });
            return;
        } else {
            try req.respond("Not Found", .{ .status = .not_found });
            return;
        }
    }
    try req.respond("Bad Request", .{ .status = .bad_request });
}

pub fn handleRefreshMetadata(req: *std.http.Server.Request, io: std.Io, req_alloc: std.mem.Allocator, username: []const u8, target: []const u8, config: config_mod.Config) !void {
    const photo_uuid = target[12 .. target.len - 17];
    if (photo_uuid.len == 36) {
        if (try db.getPhotoLocationForUser(username, photo_uuid, req_alloc)) |loc| {
            if (!std.mem.eql(u8, loc.username, username)) {
                try req.respond("Forbidden", .{ .status = .forbidden });
                return;
            }
            const is_video = std.mem.eql(u8, loc.extension, "mp4") or std.mem.eql(u8, loc.extension, "mov") or std.mem.eql(u8, loc.extension, "m4v") or std.mem.eql(u8, loc.extension, "webm") or std.mem.eql(u8, loc.extension, "avi");
            const orig_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.originals_dir, loc.username, loc.year, loc.month, photo_uuid, loc.extension });
            
            if (is_video) {
                const video_record = try video_meta_mod.extractVideoMetadata(req_alloc, io, orig_path, photo_uuid);
                defer {
                    @setEvalBranchQuota(10000);
                    inline for (comptime std.meta.fieldNames(db.VideoMetadataRecord)) |field_name| {
                        if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                            if (@field(video_record, field_name)) |v| req_alloc.free(v);
                        }
                    }
                    req_alloc.free(video_record.uuid);
                }
                try db.insertVideoMetadata(loc.username, video_record);
            } else {
                const file_buf = blk: {
                    var file = try std.Io.Dir.cwd().openFile(io, orig_path, .{});
                    defer file.close(io);
                    const file_size = try file.stat(io);
                    const buf = try req_alloc.alloc(u8, @intCast(file_size.size));
                    _ = try file.readPositionalAll(io, buf, 0);
                    break :blk buf;
                };
                const exif_record = try exif_mod.extractFullExifFromBuffer(req_alloc, file_buf, photo_uuid);
                defer {
                    @setEvalBranchQuota(10000);
                    inline for (comptime std.meta.fieldNames(db.PhotoExifRecord)) |field_name| {
                        if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                            if (@field(exif_record, field_name)) |v| req_alloc.free(v);
                        }
                    }
                    req_alloc.free(exif_record.uuid);
                }
                try db.insertPhotoExif(loc.username, exif_record);
            }
            try req.respond("", .{ .status = .ok });
            return;
        }
    }
    try req.respond("Bad Request", .{ .status = .bad_request });
}

pub fn handleGetPhotoDate(req: *std.http.Server.Request, req_alloc: std.mem.Allocator, username: []const u8, target: []const u8) !void {
    const raw_photo_uuid = target[12 .. target.len - 5];
    if (raw_photo_uuid.len == 36) {
        const photo_uuid = try req_alloc.dupe(u8, raw_photo_uuid);
        if (try db.getPhotoDate(username, photo_uuid, req_alloc)) |date_str| {
            const Response = struct {
                date: []const u8,
            };
            const resp = Response{ .date = date_str };
            var aw: std.Io.Writer.Allocating = .init(req_alloc);
            try std.json.Stringify.value(resp, .{}, &aw.writer);
            try req.respond(aw.written(), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                },
            });
            return;
        } else {
            try req.respond("Not Found", .{ .status = .not_found });
            return;
        }
    }
    try req.respond("Bad Request", .{ .status = .bad_request });
}

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;

pub fn handleChangeDate(req: *std.http.Server.Request, req_alloc: std.mem.Allocator, username: []const u8, target: []const u8, config: config_mod.Config) !void {
    const raw_photo_uuid = target[12 .. target.len - 5];
    if (raw_photo_uuid.len == 36) {
        const photo_uuid = try req_alloc.dupe(u8, raw_photo_uuid);
        var buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&buf);
        const body_str = r.allocRemaining(req_alloc, .limited(4 * 1024)) catch |err| {
            std.debug.print("Failed to read body: {}\n", .{err});
            try req.respond("Bad Request", .{ .status = .bad_request });
            return;
        };
        defer req_alloc.free(body_str);

        const ChangeDateRequest = struct {
            date: []const u8,
        };

        const parsed = std.json.parseFromSlice(
            ChangeDateRequest,
            req_alloc,
            body_str,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            std.debug.print("JSON parse error: {}\n", .{err});
            try req.respond("Invalid JSON", .{ .status = .bad_request });
            return;
        };
        defer parsed.deinit();

        const new_date_str = parsed.value.date;
        if (new_date_str.len < 19) {
            try req.respond("Bad Request: invalid date", .{ .status = .bad_request });
            return;
        }

        const new_year = new_date_str[0..4];
        const new_month = new_date_str[5..7];
        const new_day = new_date_str[8..10];
        const new_shooting_date = try std.fmt.allocPrint(req_alloc, "{s} {s}", .{ new_date_str[0..10], new_date_str[11..19] });
        defer req_alloc.free(new_shooting_date);

        if (try db.getPhotoLocationForUser(username, photo_uuid, req_alloc)) |loc| {
            if (!std.mem.eql(u8, loc.username, username)) {
                try req.respond("Forbidden", .{ .status = .forbidden });
                return;
            }

            const is_video = std.mem.eql(u8, loc.extension, "mp4") or std.mem.eql(u8, loc.extension, "mov") or std.mem.eql(u8, loc.extension, "m4v") or std.mem.eql(u8, loc.extension, "webm") or std.mem.eql(u8, loc.extension, "avi");

            if (!std.mem.eql(u8, loc.year, new_year) or !std.mem.eql(u8, loc.month, new_month)) {
                // Relocate original
                const old_orig_path = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.originals_dir, loc.username, loc.year, loc.month, photo_uuid, loc.extension }, 0);
                const new_orig_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.originals_dir, loc.username, new_year, new_month });
                const new_orig_path = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}.{s}", .{ new_orig_dir, photo_uuid, loc.extension }, 0);
                
                server.makeDirPathSync(req_alloc, new_orig_dir) catch {};
                _ = rename(old_orig_path.ptr, new_orig_path.ptr);

                if (is_video) {
                    // thumbnail (.jpg)
                    const old_thumb = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}/{s}/{s}/{s}.jpg", .{ config.thumbnails_dir, loc.username, loc.year, loc.month, photo_uuid }, 0);
                    const new_thumb_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.thumbnails_dir, loc.username, new_year, new_month });
                    const new_thumb = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}.jpg", .{ new_thumb_dir, photo_uuid }, 0);
                    server.makeDirPathSync(req_alloc, new_thumb_dir) catch {};
                    _ = rename(old_thumb.ptr, new_thumb.ptr);

                    // hover preview (.mp4)
                    const old_hover = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}/{s}/{s}/{s}.mp4", .{ config.hover_previews_dir, loc.username, loc.year, loc.month, photo_uuid }, 0);
                    const new_hover_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.hover_previews_dir, loc.username, new_year, new_month });
                    const new_hover = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}.mp4", .{ new_hover_dir, photo_uuid }, 0);
                    server.makeDirPathSync(req_alloc, new_hover_dir) catch {};
                    _ = rename(old_hover.ptr, new_hover.ptr);
                } else {
                    // preview
                    const old_prev = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.previews_dir, loc.username, loc.year, loc.month, photo_uuid, loc.extension }, 0);
                    const new_prev_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.previews_dir, loc.username, new_year, new_month });
                    const new_prev = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}.{s}", .{ new_prev_dir, photo_uuid, loc.extension }, 0);
                    server.makeDirPathSync(req_alloc, new_prev_dir) catch {};
                    _ = rename(old_prev.ptr, new_prev.ptr);

                    // thumbnail
                    const old_thumb = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.thumbnails_dir, loc.username, loc.year, loc.month, photo_uuid, loc.extension }, 0);
                    const new_thumb_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.thumbnails_dir, loc.username, new_year, new_month });
                    const new_thumb = try std.fmt.allocPrintSentinel(req_alloc, "{s}/{s}.{s}", .{ new_thumb_dir, photo_uuid, loc.extension }, 0);
                    server.makeDirPathSync(req_alloc, new_thumb_dir) catch {};
                    _ = rename(old_thumb.ptr, new_thumb.ptr);
                }
            }

            try db.updatePhotoDate(loc.username, photo_uuid, new_year, new_month, new_day, new_shooting_date);
            try req.respond("", .{ .status = .ok });
            return;
        }
    }
    try req.respond("Bad Request", .{ .status = .bad_request });
}

pub fn handleDeletePhoto(req: *std.http.Server.Request, io: std.Io, req_alloc: std.mem.Allocator, username: []const u8, target: []const u8, config: config_mod.Config) !void {
    const photo_uuid = target[8..];

    const loc = try db.getPhotoLocationForUser(username, photo_uuid, req_alloc);
    if (loc) |l| {
        if (std.mem.eql(u8, l.username, username)) {
            const orig_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.originals_dir, l.username, l.year, l.month, photo_uuid, l.extension });
            const prev_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.previews_dir, l.username, l.year, l.month, photo_uuid, l.extension });
            const thumb_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.thumbnails_dir, l.username, l.year, l.month, photo_uuid, l.extension });
            const hover_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.mp4", .{ config.hover_previews_dir, l.username, l.year, l.month, photo_uuid });

            const cwd = std.Io.Dir.cwd();
            cwd.deleteFile(io, orig_path) catch |err| std.debug.print("Failed to delete orig: {}\n", .{err});
            cwd.deleteFile(io, prev_path) catch |err| std.debug.print("Failed to delete prev: {}\n", .{err});
            cwd.deleteFile(io, thumb_path) catch |err| std.debug.print("Failed to delete thumb: {}\n", .{err});
            cwd.deleteFile(io, hover_path) catch {};

            try db.deletePhoto(username, photo_uuid);

            try req.respond("Deleted", .{});
            return;
        } else {
            try req.respond("Forbidden", .{ .status = .forbidden });
            return;
        }
        try req.respond("Not Found", .{ .status = .not_found });
        return;
    }
}

pub fn handleDeleteBatch(req: *std.http.Server.Request, io: std.Io, req_alloc: std.mem.Allocator, username: []const u8, config: config_mod.Config) !void {
    var buf: [4096]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body_str = r.allocRemaining(req_alloc, .limited(4 * 1024)) catch |err| {
        std.debug.print("Failed to read body: {}\n", .{err});
        try req.respond("Bad Request", .{ .status = .bad_request });
        return;
    };
    defer req_alloc.free(body_str);

    // Parse URL encoded body. We expect "uuids=uuid1,uuid2,uuid3"
    var uuids_str: ?[]const u8 = null;
    var form_it = std.mem.tokenizeSequence(u8, body_str, "&");
    while (form_it.next()) |pair| {
        var kv_it = std.mem.splitScalar(u8, pair, '=');
        const k = kv_it.first();
        if (std.mem.eql(u8, k, "uuids")) {
            if (kv_it.next()) |v| {
                uuids_str = try server.decodeUrl(req_alloc, v);
            }
        }
    }

    if (uuids_str) |s| {
        defer req_alloc.free(s);
        var uuid_it = std.mem.splitScalar(u8, s, ',');
        while (uuid_it.next()) |uuid| {
            const trimmed = std.mem.trim(u8, uuid, " ");
            if (trimmed.len != 36) continue;
            
            const loc = try db.getPhotoLocationForUser(username, trimmed, req_alloc);
            if (loc) |l| {
                if (std.mem.eql(u8, l.username, username)) {
                    const orig_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.originals_dir, l.username, l.year, l.month, trimmed, l.extension });
                    const prev_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.previews_dir, l.username, l.year, l.month, trimmed, l.extension });
                    const thumb_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{ config.thumbnails_dir, l.username, l.year, l.month, trimmed, l.extension });
                    const hover_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}/{s}.mp4", .{ config.hover_previews_dir, l.username, l.year, l.month, trimmed });

                    const cwd = std.Io.Dir.cwd();
                    cwd.deleteFile(io, orig_path) catch {};
                    cwd.deleteFile(io, prev_path) catch {};
                    cwd.deleteFile(io, thumb_path) catch {};
                    cwd.deleteFile(io, hover_path) catch {};

                    try db.deletePhoto(username, trimmed);
                }
            }
        }
    }

    // HTMX responds with HX-Redirect to refresh page
    try req.respond("", .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "HX-Redirect", .value = "/" },
        },
    });
}

