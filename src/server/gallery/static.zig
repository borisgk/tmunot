const std = @import("std");
const db = @import("../../db.zig");
const server = @import("../../server.zig");
const processor = @import("../../processor.zig");
const config_mod = @import("../../config.zig");

extern "c" fn time(t: ?*i64) i64;
pub fn serveStaticFile(allocator: std.mem.Allocator, req: *std.http.Server.Request, io: std.Io, is_authenticated: bool, config: config_mod.Config) !bool {
    _ = allocator; // kept for API compatibility; we use a local arena below
    const target = req.head.target;

    if (std.mem.startsWith(u8, target, "/thumbnails/") or std.mem.startsWith(u8, target, "/previews/") or std.mem.startsWith(u8, target, "/hover_previews/")) {
        // Use a fresh per-request arena so concurrent requests don't share the same allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return true;
        }

        // Decode URL encoding (e.g. %20 -> space)
        const decoded_target = try server.decodeUrl(alloc, target);

        var type_segment: []const u8 = undefined;
        var suffix: []const u8 = undefined;
        if (std.mem.startsWith(u8, decoded_target, "/thumbnails/")) {
            type_segment = "thumbnails";
            suffix = decoded_target[12..];
        } else if (std.mem.startsWith(u8, decoded_target, "/hover_previews/")) {
            type_segment = "hover_previews";
            suffix = decoded_target[16..];
        } else {
            type_segment = "previews";
            suffix = decoded_target[10..];
        }

        // Suffix is "<uuid>.<ext>". Extract uuid (everything before the dot)
        const dot_idx = std.mem.indexOfScalar(u8, suffix, '.') orelse {
            try req.respond("Bad Request", .{ .status = .bad_request });
            return true;
        };
        const uuid = suffix[0..dot_idx];

        // Shield SQLite from polling: if the job is active in registry, return 404 immediately
        if (try processor.getActiveJob(uuid, alloc)) |_| {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }

        // Retrieve properties from SQLite
        const loc = try db.getPhotoLocation(uuid, alloc);
        if (loc == null) {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }

        // Conditional Request validation for aggressive browser caching (F5/Reload support)
        var if_none_match: ?[]const u8 = null;
        var header_it = req.iterateHeaders();
        while (header_it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "if-none-match")) {
                if_none_match = std.mem.trim(u8, header.value, " \"");
            }
        }

        const etag_val = try std.fmt.allocPrint(alloc, "\"{s}\"", .{uuid});

        if (if_none_match) |etag| {
            var clean_etag = etag;
            if (std.mem.startsWith(u8, clean_etag, "W/") or std.mem.startsWith(u8, clean_etag, "w/")) {
                clean_etag = clean_etag[2..];
            }
            clean_etag = std.mem.trim(u8, clean_etag, " \"");

            if (std.mem.eql(u8, clean_etag, uuid)) {
                try req.respond("", .{
                    .status = .not_modified,
                    .extra_headers = &.{
                        .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                        .{ .name = "ETag", .value = etag_val },
                    },
                });
                return true;
            }
        }

        // Reconstruct local chronological user path: photos/<username>/<type>/<year>/<month>/<uuid>.<extension>
        const is_video = std.mem.eql(u8, loc.?.extension, "mp4") or
                         std.mem.eql(u8, loc.?.extension, "mov") or
                         std.mem.eql(u8, loc.?.extension, "m4v") or
                         std.mem.eql(u8, loc.?.extension, "webm") or
                         std.mem.eql(u8, loc.?.extension, "avi");

        const type_folder = if (std.mem.eql(u8, type_segment, "previews") and is_video)
            @as([]const u8, "originals")
        else
            type_segment;

        const file_ext = if (std.mem.eql(u8, type_segment, "hover_previews"))
            @as([]const u8, "mp4")
        else if (std.mem.eql(u8, type_segment, "thumbnails") and is_video)
            @as([]const u8, "jpg")
        else
            loc.?.extension;

        const base_dir = if (std.mem.eql(u8, type_folder, "originals")) config.originals_dir
            else if (std.mem.eql(u8, type_folder, "previews")) config.previews_dir
            else if (std.mem.eql(u8, type_folder, "thumbnails")) config.thumbnails_dir
            else config.hover_previews_dir;

        const full_path = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}/{s}/{s}.{s}", .{
            base_dir,
            loc.?.username,
            loc.?.year,
            loc.?.month,
            uuid,
            file_ext,
        });

        var file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };

        const is_png = std.mem.eql(u8, loc.?.extension, "png");
        const mime_type = if (std.mem.eql(u8, type_segment, "hover_previews"))
            @as([]const u8, "video/mp4")
        else if (std.mem.eql(u8, type_segment, "previews") and is_video) blk: {
            if (std.mem.eql(u8, loc.?.extension, "mov")) break :blk @as([]const u8, "video/quicktime");
            if (std.mem.eql(u8, loc.?.extension, "webm")) break :blk @as([]const u8, "video/webm");
            if (std.mem.eql(u8, loc.?.extension, "avi")) break :blk @as([]const u8, "video/x-msvideo");
            break :blk @as([]const u8, "video/mp4");
        } else if (is_png)
            @as([]const u8, "image/png")
        else
            @as([]const u8, "image/jpeg");

        var send_buffer: [8192]u8 = undefined;
        var response = req.respondStreaming(&send_buffer, .{
            .content_length = stat.size,
            .respond_options = .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = mime_type },
                    .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                    .{ .name = "ETag", .value = etag_val },
                },
            },
        }) catch {
            std.debug.print("Failed to initiate streaming response\n", .{});
            return true;
        };

        var file_reader = file.reader(io, &.{});
        var chunk_buf: [65536]u8 = undefined;
        var bytes_left: u64 = stat.size;
        
        while (bytes_left > 0) {
            const to_read = @min(bytes_left, chunk_buf.len);
            const read_amt = file_reader.interface.readSliceShort(chunk_buf[0..to_read]) catch |err| {
                std.debug.print("Failed to read file chunk: {}\n", .{err});
                break;
            };
            if (read_amt == 0) break;
            response.writer.writeAll(chunk_buf[0..read_amt]) catch |err| {
                std.debug.print("Failed to write chunk to client: {}\n", .{err});
                break;
            };
            bytes_left -= read_amt;
        }

        response.end() catch |err| {
            std.debug.print("Failed to end streaming response: {}\n", .{err});
        };
        return true;
    }

    if (req.head.method == .GET and std.mem.startsWith(u8, target, "/avatars/")) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        
        const filename = try server.decodeUrl(alloc, target[9..]);
        const file_path = try std.fmt.allocPrint(alloc, "data/avatars/{s}", .{ filename });
        
        var file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };

        var mime_type: []const u8 = "image/jpeg";
        if (std.mem.endsWith(u8, filename, ".png")) mime_type = "image/png"
        else if (std.mem.endsWith(u8, filename, ".webp")) mime_type = "image/webp";

        var send_buffer: [8192]u8 = undefined;
        var response = req.respondStreaming(&send_buffer, .{
            .content_length = stat.size,
            .respond_options = .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = mime_type },
                    .{ .name = "Cache-Control", .value = "public, max-age=31536000" },
                },
            },
        }) catch return true;

        var file_reader = file.reader(io, &.{});
        var chunk_buf: [65536]u8 = undefined;
        var bytes_left: u64 = stat.size;
        while (bytes_left > 0) {
            const to_read = @min(bytes_left, chunk_buf.len);
            const read_amt = file_reader.interface.readSliceShort(chunk_buf[0..to_read]) catch break;
            if (read_amt == 0) break;
            response.writer.writeAll(chunk_buf[0..read_amt]) catch break;
            bytes_left -= read_amt;
        }
        response.end() catch {};
        return true;
    }

    if (std.mem.startsWith(u8, target, "/fonts/")) {
        const font_name = target[7..];
        if (std.mem.eql(u8, font_name, "RobotoFlex-VariableFont.woff2")) {
            try req.respond(@embedFile("../../fonts/RobotoFlex-VariableFont.woff2"), .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "font/woff2" },
                    .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                },
            });
            return true;
        }
    }

    return false;
}
