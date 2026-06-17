const std = @import("std");
const db = @import("../db.zig");
const exif = @import("../exif.zig");
const video_meta = @import("../video_meta.zig");
const config_mod = @import("../config.zig");
const auth = @import("../auth.zig");

pub fn refreshMetadataTask(io: std.Io, allocator: std.mem.Allocator, auth_ctx: *auth.AuthContext, config: config_mod.Config) void {
    std.debug.print("[REFRESH] Starting global metadata refresh...\n", .{});
    
    const users = auth_ctx.getUsers(allocator) catch |err| {
        std.debug.print("[REFRESH] Failed to get users: {}\n", .{err});
        return;
    };
    defer {
        for (users) |u| {
            allocator.free(u.username);
            allocator.free(u.real_name);
            if (u.avatar_ext) |ae| allocator.free(ae);
        }
        allocator.free(users);
    }

    for (users) |user| {
        std.debug.print("[REFRESH] Processing user: {s}\n", .{user.username});
        refreshUserMetadata(io, allocator, user.username, config) catch |err| {
            std.debug.print("[REFRESH] Error processing user {s}: {}\n", .{user.username, err});
        };
    }
    
    std.debug.print("[REFRESH] Global metadata refresh completed.\n", .{});
}

fn refreshUserMetadata(io: std.Io, allocator: std.mem.Allocator, username: []const u8, config: config_mod.Config) !void {
    const photos = try db.getUserPhotos(username, allocator);
    defer {
        for (photos) |p| {
            allocator.free(p.uuid);
            allocator.free(p.username);
            allocator.free(p.filename);
            allocator.free(p.extension);
            allocator.free(p.year);
            allocator.free(p.month);
            allocator.free(p.day);
            if (p.shooting_date) |sd| allocator.free(sd);
            allocator.free(p.upload_date);
        }
        allocator.free(photos);
    }

    for (photos) |photo| {
        processPhotoMetadata(io, allocator, username, photo, config) catch |err| {
            std.debug.print("[REFRESH] Error processing photo {s}: {}\n", .{photo.uuid, err});
        };
    }
}

fn processPhotoMetadata(io: std.Io, allocator: std.mem.Allocator, username: []const u8, photo: db.PhotoRecord, config: config_mod.Config) !void {
    const orig_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}/{s}.{s}", .{
        config.originals_dir, username, photo.year, photo.month, photo.uuid, photo.extension
    });
    defer allocator.free(orig_path);

    const is_video = std.mem.eql(u8, photo.extension, "mp4") or
                     std.mem.eql(u8, photo.extension, "mov") or
                     std.mem.eql(u8, photo.extension, "m4v") or
                     std.mem.eql(u8, photo.extension, "webm") or
                     std.mem.eql(u8, photo.extension, "avi");

    if (is_video) {
        const video_record = try video_meta.extractVideoMetadata(allocator, io, orig_path, photo.uuid);
        defer {
            @setEvalBranchQuota(10000);
            inline for (comptime std.meta.fieldNames(db.VideoMetadataRecord)) |field_name| {
                if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                    if (@field(video_record, field_name)) |v| allocator.free(v);
                }
            }
            allocator.free(video_record.uuid);
        }
        try db.pushDbInsertVideoMetadata(username, video_record);
        
        // Update basic photo info if needed (dimensions, etc)
        var updated_photo = photo;
        var changed = false;
        
        if (video_record.width) |w_str| {
            if (std.fmt.parseInt(i32, w_str, 10)) |w| {
                if (photo.width == null or photo.width.? != w) {
                    updated_photo.width = w;
                    changed = true;
                }
            } else |_| {}
        }
        if (video_record.height) |h_str| {
            if (std.fmt.parseInt(i32, h_str, 10)) |h| {
                if (photo.height == null or photo.height.? != h) {
                    updated_photo.height = h;
                    changed = true;
                }
            } else |_| {}
        }
        
        if (changed) {
            try db.pushDbInsertPhoto(updated_photo);
        }
    } else {
        const file_buf = blk: {
            const cwd = std.Io.Dir.cwd();
            var f = try cwd.openFile(io, orig_path, .{});
            defer f.close(io);
            const size = (try f.stat(io)).size;
            const buf = try allocator.alloc(u8, @intCast(size));
            var reader = f.reader(io, &.{});
            try reader.interface.readSliceAll(buf);
            break :blk buf;
        };
        defer allocator.free(file_buf);

        const full_exif_record = try exif.extractFullExifFromBuffer(allocator, file_buf, photo.uuid);
        defer {
            @setEvalBranchQuota(10000);
            inline for (comptime std.meta.fieldNames(db.PhotoExifRecord)) |field_name| {
                if (comptime std.mem.eql(u8, field_name, "uuid")) {
                    allocator.free(full_exif_record.uuid);
                } else {
                    if (@field(full_exif_record, field_name)) |v| allocator.free(v);
                }
            }
        }
        try db.pushDbInsertPhotoExif(username, full_exif_record);

        const metadata = try exif.extractExifFromBuffer(allocator, file_buf);
        defer if (metadata.shooting_date) |sd| allocator.free(sd);

        var updated_photo = photo;
        var changed = false;

        if (metadata.width) |w| {
            if (photo.width == null or photo.width.? != w) {
                updated_photo.width = w;
                changed = true;
            }
        }
        if (metadata.height) |h| {
            if (photo.height == null or photo.height.? != h) {
                updated_photo.height = h;
                changed = true;
            }
        }
        if (metadata.shooting_date) |sd| {
            if (photo.shooting_date == null or !std.mem.eql(u8, photo.shooting_date.?, sd)) {
                updated_photo.shooting_date = sd;
                changed = true;
            }
        }

        if (changed) {
            try db.pushDbInsertPhoto(updated_photo);
        }
    }
}
