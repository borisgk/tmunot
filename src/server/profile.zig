const std = @import("std");
const auth = @import("../auth.zig");
const db = @import("../db.zig");
const templates = @import("gallery/templates.zig");

pub fn handleProfileApi(req: *std.http.Server.Request, io: std.Io, req_alloc: std.mem.Allocator, auth_ctx: *auth.AuthContext, username: []const u8, target: []const u8) !void {
    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/profile-modal")) {
        const u_opt = try db.getUser(username, req_alloc);
        const u = u_opt orelse {
            try req.respond("User not found", .{ .status = .not_found });
            return;
        };
        defer {
            req_alloc.free(u.username);
            req_alloc.free(u.password_hash);
            req_alloc.free(u.real_name);
            if (u.avatar_ext) |ext| req_alloc.free(ext);
        }

        var aw = std.Io.Writer.Allocating.init(req_alloc);
        defer aw.deinit();
        try templates.renderProfileModal(&aw.writer, u.username, u.real_name);
        const final_html = try aw.toOwnedSlice();

        try req.respond(final_html, .{ .extra_headers = &.{.{ .name = "content-type", .value = "text/html" }} });
        return;
    }

    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/users/me")) {
        const u_opt = try db.getUser(username, req_alloc);
        const u = u_opt orelse {
            try req.respond("User not found", .{ .status = .not_found });
            return;
        };
        defer {
            req_alloc.free(u.username);
            req_alloc.free(u.password_hash);
            req_alloc.free(u.real_name);
            if (u.avatar_ext) |ext| req_alloc.free(ext);
        }

        const ext_str = if (u.avatar_ext) |ext| ext else "";
        const json = try std.fmt.allocPrint(req_alloc, "{{\"username\":\"{s}\",\"real_name\":\"{s}\",\"is_admin\":{},\"avatar_ext\":\"{s}\"}}", .{
            u.username, u.real_name, u.is_admin, ext_str
        });
        
        try req.respond(json, .{ .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
        return;
    }

    if (req.head.method == .PUT and std.mem.eql(u8, target, "/api/users/me")) {
        var read_buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&read_buf);
        const body_str = r.allocRemaining(req_alloc, .limited(1024 * 64)) catch {
            try req.respond("Payload too large", .{ .status = .payload_too_large });
            return;
        };
        
        const parsed = std.json.parseFromSlice(std.json.Value, req_alloc, body_str, .{}) catch {
            try req.respond("Invalid JSON", .{ .status = .bad_request });
            return;
        };
        
        if (parsed.value != .object) {
            try req.respond("Invalid JSON", .{ .status = .bad_request });
            return;
        }

        const obj = parsed.value.object;
        var new_pwd: ?[]const u8 = null;
        if (obj.get("password")) |p| {
            if (p == .string and p.string.len > 0) new_pwd = p.string;
        }

        var new_real_name: ?[]const u8 = null;
        if (obj.get("real_name")) |rn| {
            if (rn == .string) new_real_name = rn.string;
        }

        if (new_pwd == null and new_real_name == null) {
            try req.respond("Nothing to update", .{ .status = .bad_request });
            return;
        }

        try auth_ctx.editUser(username, new_pwd, new_real_name, null, null);
        try req.respond("Updated", .{});
        return;
    }

    if (req.head.method == .POST and std.mem.eql(u8, target, "/api/users/me/avatar")) {
        // Find extension from Content-Type
        var ext: []const u8 = "jpg";
        var it = req.iterateHeaders();
        while (it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
                if (std.mem.indexOf(u8, header.value, "image/png") != null) {
                    ext = "png";
                } else if (std.mem.indexOf(u8, header.value, "image/jpeg") != null) {
                    ext = "jpg";
                } else if (std.mem.indexOf(u8, header.value, "image/webp") != null) {
                    ext = "webp";
                }
            }
        }

        var read_buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&read_buf);
        const body_str = r.allocRemaining(req_alloc, .limited(5 * 1024 * 1024)) catch {
            try req.respond("Payload too large", .{ .status = .payload_too_large });
            return;
        };

        if (body_str.len == 0) {
            try req.respond("Empty body", .{ .status = .bad_request });
            return;
        }

        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(io, "data/avatars") catch |err| {
            if (err != error.PathAlreadyExists) {
                try req.respond("Internal Error", .{ .status = .internal_server_error });
                return;
            }
        };

        const file_path = try std.fmt.allocPrint(req_alloc, "data/avatars/{s}.{s}", .{ username, ext });
        var file = try cwd.createFile(io, file_path, .{});
        defer file.close(io);

        var writer = file.writer(io, &.{});
        try writer.interface.writeAll(body_str);

        try auth_ctx.editUser(username, null, null, null, ext);

        try req.respond("Avatar updated", .{});
        return;
    }

    try req.respond("Not Found", .{ .status = .not_found });
}
