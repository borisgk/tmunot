const std = @import("std");
const vips = @import("vips.zig");
const config_mod = @import("config.zig");
const processor = @import("processor.zig");
const server = @import("server.zig");
const auth = @import("auth.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Load config
    const config = try config_mod.loadConfig(allocator, io, "config.json");
    defer allocator.free(config.backend);
    defer allocator.free(config.input_directory);
    defer {
        for (config.outputs) |out| {
            allocator.free(out.name);
            allocator.free(out.directory);
        }
        allocator.free(config.outputs);
    }

    std.debug.print("Using backend: {s}\n", .{config.backend});
    std.debug.print("Quality: {d}, Outputs: {d}\n", .{ config.quality, config.outputs.len });

    std.debug.print("Skipping photo conversion on startup for now.\n", .{});

    // Initialize AuthContext
    var auth_ctx = try auth.AuthContext.init(allocator, io, "users.json");
    defer auth_ctx.deinit();

    // 7. Start web server
    try server.startServer(init.io, auth_ctx);
}
