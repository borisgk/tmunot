const std = @import("std");
const auth = @import("auth.zig");
const config_mod = @import("config.zig");
const processor = @import("processor.zig");
const db = @import("db.zig");
const core = @import("db/core.zig");
const video_meta_mod = @import("video_meta.zig");
const exif_mod = @import("exif.zig");

const server_gallery = @import("server/gallery.zig");
const server_auth = @import("server/auth.zig");
const server_upload = @import("server/upload.zig");
const server_admin = @import("server/admin.zig");
const server_profile = @import("server/profile.zig");
const server_photos = @import("server/photos.zig");

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;
extern "c" fn mkdir(path: [*c]const u8, mode: c_uint) c_int;

pub fn makeDirPathSync(allocator: std.mem.Allocator, target_dir: []const u8) !void {
    if (target_dir.len == 0) return;
    var it = std.mem.splitScalar(u8, target_dir, '/');
    var current_path = std.ArrayList(u8).empty;
    defer current_path.deinit(allocator);
    if (target_dir[0] == '/') {
        try current_path.append(allocator, '/');
    }
    while (it.next()) |component| {
        if (component.len == 0) continue;
        if (current_path.items.len > 0 and current_path.items[current_path.items.len - 1] != '/') {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, component);
        const path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{current_path.items}, 0);
        defer allocator.free(path_c);
        _ = mkdir(path_c.ptr, 0o777);
    }
}

// Helper to decode URL-encoded string (modifies in place, returns slice, or allocates)
pub fn decodeUrl(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, encoded.len);
    var i: usize = 0;
    var j: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%') {
            if (i + 2 < encoded.len) {
                const hex = encoded[i + 1 .. i + 3];
                const char = std.fmt.parseInt(u8, hex, 16) catch {
                    out[j] = encoded[i];
                    j += 1;
                    i += 1;
                    continue;
                };
                out[j] = char;
                j += 1;
                i += 3;
            } else {
                out[j] = encoded[i];
                j += 1;
                i += 1;
            }
        } else if (encoded[i] == '+') {
            out[j] = ' ';
            j += 1;
            i += 1;
        } else {
            out[j] = encoded[i];
            j += 1;
            i += 1;
        }
    }
    return allocator.realloc(out, j);
}

/// Escape HTML special characters to prevent XSS when interpolating user content into HTML.
/// Encodes: & < > " ' → &amp; &lt; &gt; &quot; &#x27;
pub fn htmlEscape(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Worst case: every char expands to 6 bytes ("&#x27;")
    var out = std.ArrayList(u8).empty;
    for (input) |c| {
        switch (c) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            '\'' => try out.appendSlice(allocator, "&#x27;"),
            else => try out.append(allocator, c),
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn startServer(io: std.Io, auth_ctx: *auth.AuthContext, config: config_mod.Config) !void {
    const address = try std.Io.net.IpAddress.parseLiteral("0.0.0.0:3001");
    var listener = try std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true });
    defer listener.deinit(io);

    std.debug.print("Starting web server on http://localhost:3001\n", .{});

    var connection_group = std.Io.Group.init;
    defer connection_group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.debug.print("Failed to accept connection: {}\n", .{err});
            continue;
        };

        connection_group.concurrent(io, handleConnection, .{ stream, io, auth_ctx, config }) catch |err| {
            std.debug.print("Failed to spawn concurrent connection handler: {}\n", .{err});
            stream.close(io);
            continue;
        };
    }
}

fn handleConnection(stream: std.Io.net.Stream, io: std.Io, auth_ctx: *auth.AuthContext, config: config_mod.Config) void {
    defer stream.close(io);
    var read_buffer: [65536]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var write_buffer: [65536]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    
    var server = std.http.Server.init(&reader.interface, &writer.interface);

    var request = server.receiveHead() catch |err| {
        if (err != error.HttpConnectionClosing) {
            std.debug.print("Failed to receive request head: {}\n", .{err});
        }
        return;
    };

    handleRequest(&request, io, stream, auth_ctx, config) catch |err| {
        std.debug.print("Error handling request: {}\n", .{err});
    };
}

fn handleRequest(req: *std.http.Server.Request, io: std.Io, stream: std.Io.net.Stream, auth_ctx: *auth.AuthContext, config: config_mod.Config) !void {
    // Per-request arena: all ephemeral allocations live here and are freed together
    // at the end of the request, regardless of which code path is taken.
    var req_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer req_arena.deinit();
    const req_alloc = req_arena.allocator();

    var is_authenticated = false;
    var username: ?[]const u8 = null;
    // username is duped into req_arena via getUsernameFromJwt; arena frees it.

    var cookie_csrf: []const u8 = "";
    var boundary_buf: [128]u8 = undefined;
    var multipart_boundary: []const u8 = "";
    var it = req.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "cookie")) {
            var cookie_it = std.mem.splitScalar(u8, header.value, ';');
            while (cookie_it.next()) |cookie| {
                const trimmed = std.mem.trim(u8, cookie, " ");
                if (std.mem.startsWith(u8, trimmed, "token=")) {
                    const token = trimmed[6..];
                    if (auth_ctx.verifyJwt(token)) {
                        is_authenticated = true;
                        username = auth_ctx.getUsernameFromJwt(token, req_alloc);
                    }
                } else if (std.mem.startsWith(u8, trimmed, "csrf_token=")) {
                    cookie_csrf = trimmed[11..];
                }
            }
        } else if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
            if (std.mem.indexOf(u8, header.value, "boundary=")) |boundary_idx| {
                var b_val = header.value[boundary_idx + 9..];
                if (std.mem.indexOfScalar(u8, b_val, ';')) |semi_idx| {
                    b_val = b_val[0..semi_idx];
                }
                const trimmed = std.mem.trim(u8, b_val, " ");
                if (trimmed.len < boundary_buf.len) {
                    @memcpy(boundary_buf[0..trimmed.len], trimmed);
                    multipart_boundary = boundary_buf[0..trimmed.len];
                }
            }
        }
    }
    const target = req.head.target;
    std.debug.print("Request: {s} {s}\n", .{ @tagName(req.head.method), target });

    // Route static assets, previews, thumbnails, and fonts first
    const handled_static = try server_gallery.serveStaticFile(req_alloc, req, io, is_authenticated, username, config);
    if (handled_static) return;

    if (req.head.method == .GET and std.mem.eql(u8, target, "/")) {
        if (is_authenticated) {
            const html = try server_gallery.generateGalleryHtml(req_alloc, username orelse "admin", config.gallery_thumbnail_height);
            defer std.heap.page_allocator.free(html);
            try req.respond(html, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/html" },
                    .{ .name = "cache-control", .value = "no-store, no-cache, must-revalidate, proxy-revalidate" },
                    .{ .name = "pragma", .value = "no-cache" },
                    .{ .name = "expires", .value = "0" },
                },
            });
            return;
        }

        const csrf = try auth_ctx.generateCsrfToken(req_alloc);

        const login_html = @embedFile("login_gen.html");
        const size = std.mem.replacementSize(u8, login_html, "<!-- CSRF_TOKEN -->", csrf);
        const final_html = try req_alloc.alloc(u8, size);
        _ = std.mem.replace(u8, login_html, "<!-- CSRF_TOKEN -->", csrf, final_html);

        const size2 = std.mem.replacementSize(u8, final_html, "<!-- ERROR_MESSAGE -->", "");
        const final_html_clean = try req_alloc.alloc(u8, size2);
        _ = std.mem.replace(u8, final_html, "<!-- ERROR_MESSAGE -->", "", final_html_clean);

        const cookie_header = try std.fmt.allocPrint(req_alloc, "csrf_token={s}; HttpOnly; SameSite=Lax; Path=/", .{csrf});

        try req.respond(final_html_clean, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "set-cookie", .value = cookie_header },
            },
        });
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/albums")) {
        if (!is_authenticated or username == null) {
            try req.respond("", .{
                .status = .see_other,
                .extra_headers = &.{
                    .{ .name = "location", .value = "/" },
                },
            });
            return;
        }

        const html = try server_gallery.generateAlbumsHtml(req_alloc, username orelse "admin");
        defer std.heap.page_allocator.free(html);
        try req.respond(html, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "cache-control", .value = "no-store, no-cache, must-revalidate, proxy-revalidate" },
                .{ .name = "pragma", .value = "no-cache" },
                .{ .name = "expires", .value = "0" },
            },
        });
        return;
    }

    if (req.head.method == .GET and std.mem.startsWith(u8, target, "/albums/")) {
        if (!is_authenticated or username == null) {
            try req.respond("", .{
                .status = .see_other,
                .extra_headers = &.{
                    .{ .name = "location", .value = "/" },
                },
            });
            return;
        }

        const album_uuid = target[8..];
        if (album_uuid.len == 36) {
            const html_opt = try server_gallery.generateAlbumDetailHtml(req_alloc, username.?, album_uuid, config.gallery_thumbnail_height);
            if (html_opt) |html| {
                defer std.heap.page_allocator.free(html);
                try req.respond(html, .{
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/html" },
                        .{ .name = "cache-control", .value = "no-store, no-cache, must-revalidate, proxy-revalidate" },
                        .{ .name = "pragma", .value = "no-cache" },
                        .{ .name = "expires", .value = "0" },
                    },
                });
                return;
            }
        }

        try req.respond("Not Found", .{ .status = .not_found });
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/albums")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_gallery.handleListAlbums(req, req_alloc, username.?);
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/api/albums")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_gallery.handleCreateAlbum(req, req_alloc, username.?);
        return;
    }

    if (req.head.method == .POST and std.mem.startsWith(u8, target, "/api/albums/") and std.mem.endsWith(u8, target, "/photos")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        const raw_album_uuid = target[12 .. target.len - 7];
        if (raw_album_uuid.len == 36) {
            const album_uuid = try req_alloc.dupe(u8, raw_album_uuid);
            try server_gallery.handleAddPhotosToAlbum(req, req_alloc, username.?, album_uuid);
            return;
        }
        try req.respond("Bad Request", .{ .status = .bad_request });
        return;
    }

    if (req.head.method == .DELETE and std.mem.startsWith(u8, target, "/api/albums/") and std.mem.indexOf(u8, target, "/photos/") != null) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        if (std.mem.indexOf(u8, target, "/photos/")) |photos_idx| {
            const album_uuid = target[12..photos_idx];
            const photo_uuid = target[photos_idx + 8..];
            if (album_uuid.len == 36 and photo_uuid.len == 36) {
                try server_gallery.handleRemovePhotoFromAlbum(req, req_alloc, username.?, album_uuid, photo_uuid);
                return;
            }
        }
        try req.respond("Bad Request", .{ .status = .bad_request });
        return;
    }

    if (req.head.method == .GET and std.mem.startsWith(u8, target, "/api/photos/") and std.mem.endsWith(u8, target, "/metadata")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_photos.handleGetMetadata(req, req_alloc, username.?, target);
        return;
    }

    if (req.head.method == .POST and std.mem.startsWith(u8, target, "/api/photos/") and std.mem.endsWith(u8, target, "/metadata/refresh")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_photos.handleRefreshMetadata(req, io, req_alloc, username.?, target, config);
        return;
    }

    if (req.head.method == .PUT and std.mem.startsWith(u8, target, "/api/photos/") and std.mem.endsWith(u8, target, "/date")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_photos.handleChangeDate(req, req_alloc, username.?, target, config);
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/upload")) {
        if (!is_authenticated or username == null) {
            try req.respond("", .{
                .status = .see_other,
                .extra_headers = &.{
                    .{ .name = "location", .value = "/" },
                },
            });
            return;
        }

        try req.respond(@embedFile("upload_gen.html"), .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "cache-control", .value = "no-cache, no-store, must-revalidate" },
            },
        });
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/upload/events")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }

        // Send custom SSE headers using the stream's writer directly
        var header_buf: [256]u8 = undefined;
        var stream_writer = stream.writer(io, &header_buf);
        try stream_writer.interface.writeAll("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n");
        try stream_writer.interface.flush(); // FLUSH HEADERS IMMEDIATELY!

        // Register the stream as an active SSE client
        try processor.addSseClient(stream, username.?);

        // Yield/keep alive stream until disconnected using non-blocking io.sleep
        while (true) {
            try io.sleep(std.Io.Duration.fromSeconds(15), .awake);
            const ok = processor.writeKeepAlive(stream) catch false;
            if (!ok) {
                processor.removeSseClient(stream);
                return;
            }
        }
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/upload")) {
        try server_upload.handleUpload(req, io, req_alloc, config, is_authenticated, username, multipart_boundary);
        return;
    }



    if (req.head.method == .GET and std.mem.eql(u8, target, "/users")) {
        if (!is_authenticated or username == null) {
            try req.respond("", .{
                .status = .see_other,
                .extra_headers = &.{
                    .{ .name = "location", .value = "/" },
                },
            });
            return;
        }

        if (!auth_ctx.isAdmin(username.?)) {
            try req.respond("Forbidden", .{ .status = .forbidden });
            return;
        }

        try req.respond(@embedFile("users_gen.html"), .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "cache-control", .value = "no-cache, no-store, must-revalidate" },
            },
        });
        return;
    }

    if (std.mem.startsWith(u8, target, "/api/admin/")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        if (!auth_ctx.isAdmin(username.?)) {
            try req.respond("Forbidden", .{ .status = .forbidden });
            return;
        }
        try server_admin.handleAdminApi(req, io, req_alloc, auth_ctx, config, username.?);
        return;
    }

    if (std.mem.startsWith(u8, target, "/api/users/me")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_profile.handleProfileApi(req, io, req_alloc, auth_ctx, username.?, target);
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/login")) {
        try server_auth.handleLogin(req, auth_ctx, req_alloc, cookie_csrf);
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/logout")) {
        const cookie = "token=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0";
        try req.respond("", .{
            .status = .see_other,
            .extra_headers = &.{
                .{ .name = "location", .value = "/" },
                .{ .name = "set-cookie", .value = cookie },
            },
        });
        return;
    }

    if (req.head.method == .POST and std.mem.startsWith(u8, target, "/delete/")) {
        if (!is_authenticated or username == null) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }
        try server_photos.handleDeletePhoto(req, io, req_alloc, username.?, target, config);
        return;
    }

    try req.respond("Not Found", .{ .status = .not_found });
}

test "decodeUrl" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const t1 = try decodeUrl(allocator, "hello+world");
    defer allocator.free(t1);
    try testing.expectEqualStrings("hello world", t1);

    const t2 = try decodeUrl(allocator, "hello%20world");
    defer allocator.free(t2);
    try testing.expectEqualStrings("hello world", t2);

    const t3 = try decodeUrl(allocator, "a%2Fb%3Fc%3Dd");
    defer allocator.free(t3);
    try testing.expectEqualStrings("a/b?c=d", t3);

    const t4 = try decodeUrl(allocator, "invalid%2Ghex");
    defer allocator.free(t4);
    try testing.expectEqualStrings("invalid%2Ghex", t4);
}
