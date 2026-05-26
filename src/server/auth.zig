const std = @import("std");
const auth = @import("../auth.zig");
const server = @import("../server.zig");

pub fn serveLoginError(req: *std.http.Server.Request, auth_ctx: *auth.AuthContext, req_alloc: std.mem.Allocator, err_msg: []const u8) !void {
    const csrf = try auth_ctx.generateCsrfToken(req_alloc);

    const login_html = @embedFile("../login_gen.html");
    const size = std.mem.replacementSize(u8, login_html, "<!-- CSRF_TOKEN -->", csrf);
    const final_html = try req_alloc.alloc(u8, size);
    _ = std.mem.replace(u8, login_html, "<!-- CSRF_TOKEN -->", csrf, final_html);

    const size2 = std.mem.replacementSize(u8, final_html, "<!-- ERROR_MESSAGE -->", err_msg);
    const final_html_err = try req_alloc.alloc(u8, size2);
    _ = std.mem.replace(u8, final_html, "<!-- ERROR_MESSAGE -->", err_msg, final_html_err);

    const cookie_header = try std.fmt.allocPrint(req_alloc, "csrf_token={s}; HttpOnly; SameSite=Lax; Path=/", .{csrf});

    try req.respond(final_html_err, .{
        .status = .unauthorized,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html" },
            .{ .name = "set-cookie", .value = cookie_header },
        },
    });
}

pub fn handleLogin(req: *std.http.Server.Request, auth_ctx: *auth.AuthContext, req_alloc: std.mem.Allocator, cookie_csrf: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body_str = try r.allocRemaining(req_alloc, .limited(1024 * 1024));

    var form_username: []const u8 = "";
    var form_password: []const u8 = "";
    var form_csrf: []const u8 = "";

    var form_it = std.mem.splitScalar(u8, body_str, '&');
    while (form_it.next()) |pair| {
        var kv = std.mem.splitScalar(u8, pair, '=');
        const key = kv.next() orelse continue;
        const val_encoded = kv.next() orelse continue;

        const val = try server.decodeUrl(req_alloc, val_encoded);
        if (std.mem.eql(u8, key, "username")) {
            form_username = val;
        } else if (std.mem.eql(u8, key, "password")) {
            form_password = val;
        } else if (std.mem.eql(u8, key, "csrf_token")) {
            form_csrf = val;
        }
        // All values live in req_alloc arena; no per-value free needed.
    }

    if (cookie_csrf.len == 0 or !std.mem.eql(u8, cookie_csrf, form_csrf)) {
        try serveLoginError(req, auth_ctx, req_alloc, "Invalid CSRF token");
        return;
    }

    if (auth_ctx.verifyCredentials(form_username, form_password)) {
        const jwt = try auth_ctx.generateJwt(form_username);
        defer auth_ctx.allocator.free(jwt);
        const cookie = try std.fmt.allocPrint(req_alloc, "token={s}; HttpOnly; Secure; SameSite=Lax; Path=/", .{jwt});

        try req.respond("", .{
            .status = .see_other,
            .extra_headers = &.{
                .{ .name = "location", .value = "/" },
                .{ .name = "set-cookie", .value = cookie },
            },
        });
        return;
    } else {
        try serveLoginError(req, auth_ctx, req_alloc, "Invalid username or password");
        return;
    }
}
