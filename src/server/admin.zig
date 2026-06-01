const std = @import("std");
const auth = @import("../auth.zig");
const config_mod = @import("../config.zig");

pub fn handleAdminApi(req: *std.http.Server.Request, io: std.Io, req_alloc: std.mem.Allocator, auth_ctx: *auth.AuthContext, _: config_mod.Config, username: []const u8) !void {
    const target = req.head.target;

    // GET /api/admin/config
    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/admin/config")) {
        const cwd = std.Io.Dir.cwd();
        var file = cwd.openFile(io, "config.json", .{}) catch {
            try req.respond("Error", .{ .status = .internal_server_error });
            return;
        };
        defer file.close(io);

        const stat = try file.stat(io);
        const contents = try req_alloc.alloc(u8, @intCast(stat.size));
        
        var file_reader = file.reader(io, &.{});
        _ = try file_reader.interface.readSliceAll(contents);

        try req.respond(contents, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        return;
    }

    // POST /api/admin/config
    if (req.head.method == .POST and std.mem.eql(u8, target, "/api/admin/config")) {
        var buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&buf);
        const body_str = r.allocRemaining(req_alloc, .limited(1024 * 1024)) catch {
            try req.respond("Payload too large", .{ .status = .payload_too_large });
            return;
        };

        const new_config = config_mod.parseConfigJson(req_alloc, body_str) catch {
            try req.respond("Invalid JSON", .{ .status = .bad_request });
            return;
        };

        config_mod.saveConfig(io, "config.json", new_config) catch {
            try req.respond("Error saving config", .{ .status = .internal_server_error });
            return;
        };

        try req.respond("{\"status\":\"ok\"}", .{
            .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
        });
        return;
    }

    // GET /api/admin/users
    if (req.head.method == .GET and std.mem.eql(u8, target, "/api/admin/users")) {
        const users = try auth_ctx.getUsers(req_alloc);
        var aw: std.Io.Writer.Allocating = .init(req_alloc);
        try std.json.Stringify.value(users, .{}, &aw.writer);
        try req.respond(aw.written(), .{
            .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
        });
        return;
    }

    // POST /api/admin/users
    if (req.head.method == .POST and std.mem.eql(u8, target, "/api/admin/users")) {
        var buf: [1024]u8 = undefined;
        var r = req.readerExpectNone(&buf);
        const body_str = r.allocRemaining(req_alloc, .limited(1024 * 1024)) catch {
            try req.respond("Payload too large", .{ .status = .payload_too_large });
            return;
        };

        const CreateUserReq = struct { username: []const u8, password: []const u8 };
        const parsed = std.json.parseFromSlice(CreateUserReq, req_alloc, body_str, .{ .ignore_unknown_fields = true }) catch {
            try req.respond("Invalid JSON", .{ .status = .bad_request });
            return;
        };
        defer parsed.deinit();

        auth_ctx.createUser(parsed.value.username, parsed.value.password) catch {
            try req.respond("Error creating user", .{ .status = .internal_server_error });
            return;
        };
        auth_ctx.saveUsers() catch {
            try req.respond("Error saving user", .{ .status = .internal_server_error });
            return;
        };

        try req.respond("{\"status\":\"ok\"}", .{
            .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
        });
        return;
    }

    // DELETE /api/admin/users/:username
    if (req.head.method == .DELETE and std.mem.startsWith(u8, target, "/api/admin/users/")) {
        const target_username = target[17..];
        
        // decode url first
        const decoded_username = try @import("../server.zig").decodeUrl(req_alloc, target_username);
        
        if (std.mem.eql(u8, decoded_username, username)) {
            try req.respond("Cannot delete yourself", .{ .status = .forbidden });
            return;
        }

        auth_ctx.deleteUser(decoded_username) catch |err| {
            if (err == error.UserNotFound) {
                try req.respond("Not Found", .{ .status = .not_found });
            } else {
                try req.respond("Error", .{ .status = .internal_server_error });
            }
            return;
        };

        try req.respond("{\"status\":\"ok\"}", .{
            .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" } },
        });
        return;
    }

    try req.respond("Not Found", .{ .status = .not_found });
}
