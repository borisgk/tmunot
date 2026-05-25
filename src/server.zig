const std = @import("std");
const auth = @import("auth.zig");

// Helper to decode URL-encoded string (modifies in place, returns slice, or allocates)
fn decodeUrl(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
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

pub fn startServer(io: std.Io, auth_ctx: *auth.AuthContext) !void {
    const address = try std.Io.net.IpAddress.parseLiteral("0.0.0.0:3001");
    var listener = try std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true });
    defer listener.deinit(io);

    std.debug.print("Starting web server on http://localhost:3001\n", .{});

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.debug.print("Failed to accept connection: {}\n", .{err});
            continue;
        };

        const thread = std.Thread.spawn(.{}, handleConnection, .{ stream, io, auth_ctx }) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            stream.close(io);
            continue;
        };
        thread.detach();
    }
}

fn handleConnection(stream: std.Io.net.Stream, io: std.Io, auth_ctx: *auth.AuthContext) void {
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

    handleRequest(&request, io, auth_ctx) catch |err| {
        std.debug.print("Error handling request: {}\n", .{err});
    };
}

fn handleRequest(req: *std.http.Server.Request, io: std.Io, auth_ctx: *auth.AuthContext) !void {
    var is_authenticated = false;
    var cookie_csrf: []const u8 = "";
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
        }
    }
    const target = req.head.target;
    std.debug.print("Request: {s} {s}\n", .{ @tagName(req.head.method), target });

    if (req.head.method == .GET and std.mem.startsWith(u8, target, "/fonts/")) {
        const font_name = target[7..];
        if (std.mem.eql(u8, font_name, "Roboto-Regular.ttf")) {
            try req.respond(@embedFile("fonts/Roboto-Regular.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return;
        } else if (std.mem.eql(u8, font_name, "Roboto-Medium.ttf")) {
            try req.respond(@embedFile("fonts/Roboto-Medium.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return;
        } else if (std.mem.eql(u8, font_name, "Roboto-Bold.ttf")) {
            try req.respond(@embedFile("fonts/Roboto-Bold.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return;
        }
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/")) {
        if (is_authenticated) {
            const html = try generateGalleryHtml(io);
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
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }

        // Drain the upload request body (Multipart form data) safely to avoid TCP resets
        var buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&buf);
        var discard_buf: [8192]u8 = undefined;
        while (true) {
            const amt = r.readSliceShort(&discard_buf) catch |err| {
                std.debug.print("Error draining upload body: {}\n", .{err});
                break;
            };
            if (amt == 0) break;
        }

        try req.respond("{\"status\":\"success\",\"message\":\"Images received by simulated upload handler.\"}", .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/login")) {
        var buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&buf);
        const body_str = try r.allocRemaining(auth_ctx.allocator, .limited(1024 * 1024));
        defer auth_ctx.allocator.free(body_str);

        var form_username: []const u8 = "";
        var form_password: []const u8 = "";
        var form_csrf: []const u8 = "";

        var form_it = std.mem.splitScalar(u8, body_str, '&');
        while (form_it.next()) |pair| {
            var kv = std.mem.splitScalar(u8, pair, '=');
            const key = kv.next() orelse continue;
            const val_encoded = kv.next() orelse continue;

            const val = try decodeUrl(auth_ctx.allocator, val_encoded);
            if (std.mem.eql(u8, key, "username")) {
                form_username = val;
            } else if (std.mem.eql(u8, key, "password")) {
                form_password = val;
            } else if (std.mem.eql(u8, key, "csrf_token")) {
                form_csrf = val;
            } else {
                auth_ctx.allocator.free(val);
            }
        }

        defer {
            if (form_username.len > 0) auth_ctx.allocator.free(form_username);
            if (form_password.len > 0) auth_ctx.allocator.free(form_password);
            if (form_csrf.len > 0) auth_ctx.allocator.free(form_csrf);
        }

        if (cookie_csrf.len == 0 or !std.mem.eql(u8, cookie_csrf, form_csrf)) {
            try serveLoginError(req, auth_ctx, "Invalid CSRF token");
            return;
        }

        if (auth_ctx.verifyCredentials(form_username, form_password)) {
            const jwt = try auth_ctx.generateJwt(form_username);
            defer auth_ctx.allocator.free(jwt);
            const cookie = try std.fmt.allocPrint(auth_ctx.allocator, "token={s}; HttpOnly; Secure; SameSite=Lax; Path=/", .{jwt});
            defer auth_ctx.allocator.free(cookie);

            try req.respond("", .{
                .status = .see_other,
                .extra_headers = &.{
                    .{ .name = "location", .value = "/" },
                    .{ .name = "set-cookie", .value = cookie },
                },
            });
            return;
        } else {
            try serveLoginError(req, auth_ctx, "Invalid username or password");
            return;
        }
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

    if (std.mem.startsWith(u8, target, "/thumbnails/") or std.mem.startsWith(u8, target, "/previews/")) {
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return;
        }

        var path_buf: [1024]u8 = undefined;
        const relative_path = target[1..];
        const full_path = std.fmt.bufPrint(&path_buf, "output/{s}", .{relative_path}) catch {
            try req.respond("Path too long", .{ .status = .bad_request });
            return;
        };

        var file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return;
        };

        const file_contents = std.heap.page_allocator.alloc(u8, @intCast(stat.size)) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return;
        };
        defer std.heap.page_allocator.free(file_contents);

        var reader = file.reader(io, &.{});
        reader.interface.readSliceAll(file_contents) catch |err| {
            std.debug.print("Failed to read file '{s}': {}\n", .{full_path, err});
            try req.respond("Error reading file", .{ .status = .internal_server_error });
            return;
        };

        try req.respond(file_contents, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = if (std.mem.endsWith(u8, full_path, ".png")) @as([]const u8, "image/png") else @as([]const u8, "image/jpeg") },
            },
        });
        return;
    }

    try req.respond("Not Found", .{ .status = .not_found });
}

fn serveLoginError(req: *std.http.Server.Request, auth_ctx: *auth.AuthContext, err_msg: []const u8) !void {
    const csrf = try auth_ctx.generateCsrfToken();
    defer auth_ctx.allocator.free(csrf);
    
    const login_html = @embedFile("login_gen.html");
    const size = std.mem.replacementSize(u8, login_html, "<!-- CSRF_TOKEN -->", csrf);
    const final_html = try auth_ctx.allocator.alloc(u8, size);
    defer auth_ctx.allocator.free(final_html);
    _ = std.mem.replace(u8, login_html, "<!-- CSRF_TOKEN -->", csrf, final_html);

    const size2 = std.mem.replacementSize(u8, final_html, "<!-- ERROR_MESSAGE -->", err_msg);
    const final_html_err = try auth_ctx.allocator.alloc(u8, size2);
    defer auth_ctx.allocator.free(final_html_err);
    _ = std.mem.replace(u8, final_html, "<!-- ERROR_MESSAGE -->", err_msg, final_html_err);

    const cookie_header = try std.fmt.allocPrint(auth_ctx.allocator, "csrf_token={s}; HttpOnly; SameSite=Lax; Path=/", .{csrf});
    defer auth_ctx.allocator.free(cookie_header);

    try req.respond(final_html_err, .{
        .status = .unauthorized,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html" },
            .{ .name = "set-cookie", .value = cookie_header },
        },
    });
}

fn generateGalleryHtml(io: std.Io) ![]u8 {
    const allocator = std.heap.page_allocator;
    var html = std.ArrayList(u8).empty;
    errdefer html.deinit(allocator);

    const template = @embedFile("index_gen.html");
    const placeholder = "<!-- GALLERY_CONTENT -->";
    const split_index = std.mem.indexOf(u8, template, placeholder) orelse {
        std.debug.print("Could not find GALLERY_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const header = template[0..split_index];
    const footer = template[split_index + placeholder.len ..];

    try html.appendSlice(allocator, header);

    const logout_html = 
        \\<div style="position: absolute; top: 2.5rem; right: 2.5rem; z-index: 10;">
        \\  <form method="POST" action="/logout">
        \\      <button type="submit" style="padding: 0.75rem 1.5rem; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); border: none; border-radius: var(--md-sys-shape-corner-full); cursor: pointer; font-weight: 700; font-family: inherit; font-size: 1rem; transition: transform 0.2s cubic-bezier(0.2, 0, 0, 1);" onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">Logout</button>
        \\  </form>
        \\</div>
    ;
    try html.appendSlice(allocator, logout_html);

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, "output/thumbnails", .{ .iterate = true }) catch return html.toOwnedSlice(allocator);
    defer dir.close(io);
    
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file) {
            const card = try std.fmt.allocPrint(allocator,
                \\        <div class="card" onclick="openLightbox('/previews/{s}')">
                \\            <img src="/thumbnails/{s}" alt="{s}" loading="lazy">
                \\            <p>{s}</p>
                \\        </div>
            , .{ entry.name, entry.name, entry.name, entry.name });
            try html.appendSlice(allocator, card);
        }
    }

    try html.appendSlice(allocator, footer);

    return html.toOwnedSlice(allocator);
}
