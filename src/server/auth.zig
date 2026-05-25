const std = @import("std");
const auth = @import("../auth.zig");
const server = @import("../server.zig");

pub fn serveLoginError(req: *std.http.Server.Request, auth_ctx: *auth.AuthContext, err_msg: []const u8) !void {
    const csrf = try auth_ctx.generateCsrfToken();
    defer auth_ctx.allocator.free(csrf);
    
    const login_html = @embedFile("../login_gen.html");
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

pub fn handleLogin(req: *std.http.Server.Request, auth_ctx: *auth.AuthContext, cookie_csrf: []const u8) !void {
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

        const val = try server.decodeUrl(auth_ctx.allocator, val_encoded);
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
