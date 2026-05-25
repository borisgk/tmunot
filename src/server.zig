const std = @import("std");
const auth = @import("auth.zig");
const config_mod = @import("config.zig");
const processor = @import("processor.zig");

const server_gallery = @import("server/gallery.zig");
const server_auth = @import("server/auth.zig");
const server_upload = @import("server/upload.zig");

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

pub fn startServer(io: std.Io, auth_ctx: *auth.AuthContext, config: config_mod.Config) !void {
    const address = try std.Io.net.IpAddress.parseLiteral("0.0.0.0:3001");
    var listener = try std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true });
    defer listener.deinit(io);

    std.debug.print("Starting web server on http://localhost:3001\n", .{});

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.debug.print("Failed to accept connection: {}\n", .{err});
            continue;
        };

        const thread = std.Thread.spawn(.{}, handleConnection, .{ stream, io, auth_ctx, config }) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            stream.close(io);
            continue;
        };
        thread.detach();
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

    handleRequest(&request, io, auth_ctx, config) catch |err| {
        std.debug.print("Error handling request: {}\n", .{err});
    };
}

fn handleRequest(req: *std.http.Server.Request, io: std.Io, auth_ctx: *auth.AuthContext, config: config_mod.Config) !void {
    var is_authenticated = false;
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
    const handled_static = try server_gallery.serveStaticFile(req, io, is_authenticated);
    if (handled_static) return;

    if (req.head.method == .GET and std.mem.eql(u8, target, "/")) {
        if (is_authenticated) {
            const html = try server_gallery.generateGalleryHtml(io);
            defer std.heap.page_allocator.free(html);
            try req.respond(html, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/html" },
                },
            });
            return;
        }

        const csrf = try auth_ctx.generateCsrfToken();
        defer auth_ctx.allocator.free(csrf);
        
        const login_html = @embedFile("login_gen.html");
        const size = std.mem.replacementSize(u8, login_html, "<!-- CSRF_TOKEN -->", csrf);
        const final_html = try auth_ctx.allocator.alloc(u8, size);
        defer auth_ctx.allocator.free(final_html);
        _ = std.mem.replace(u8, login_html, "<!-- CSRF_TOKEN -->", csrf, final_html);

        const size2 = std.mem.replacementSize(u8, final_html, "<!-- ERROR_MESSAGE -->", "");
        const final_html_clean = try auth_ctx.allocator.alloc(u8, size2);
        defer auth_ctx.allocator.free(final_html_clean);
        _ = std.mem.replace(u8, final_html, "<!-- ERROR_MESSAGE -->", "", final_html_clean);

        const cookie_header = try std.fmt.allocPrint(auth_ctx.allocator, "csrf_token={s}; HttpOnly; SameSite=Lax; Path=/", .{csrf});
        defer auth_ctx.allocator.free(cookie_header);

        try req.respond(final_html_clean, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
                .{ .name = "set-cookie", .value = cookie_header },
            },
        });
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/upload")) {
        if (!is_authenticated) {
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
            },
        });
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/upload")) {
        try server_upload.handleUpload(req, io, auth_ctx, config, is_authenticated, multipart_boundary);
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/login")) {
        try server_auth.handleLogin(req, auth_ctx, cookie_csrf);
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

    try req.respond("Not Found", .{ .status = .not_found });
}
