const std = @import("std");
const vips = @import("vips.zig");
const config_mod = @import("config.zig");
const processor = @import("processor.zig");
const server = @import("server.zig");
const auth = @import("auth.zig");
const db = @import("db.zig");

pub fn main(init: std.process.Init) !void {
    // The default Threaded IO caps concurrent tasks at cpu_count-1.
    // For a web server this means only (N-1) connections can be handled
    // simultaneously — uploads stall once the limit is hit.
    // We create our own Threaded instance with unlimited async concurrency.
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
        .async_limit = .unlimited,
    });
    defer threaded.deinit();
    const io = threaded.io();

    if (vips.vips_init("tmunot") != 0) {
        std.debug.print("Failed to initialize libvips\n", .{});
        return error.VipsInitFailed;
    }
    defer vips.vips_shutdown();

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();



    // 1. Load config
    const config = try config_mod.loadConfig(allocator, io, "config.json");
    defer allocator.free(config.backend);
    defer allocator.free(config.input_directory);
    defer allocator.free(config.db_dir);
    defer {
        for (config.outputs) |out| {
            allocator.free(out.name);
            allocator.free(out.directory);
        }
        allocator.free(config.outputs);
    }

    std.debug.print("Using backend: {s}\n", .{config.backend});
    std.debug.print("Quality: {d}, Outputs: {d}\n", .{ config.quality, config.outputs.len });

    // Initialize DB
    try db.init(allocator, io, config.db_dir);
    defer db.deinit();

    std.debug.print("Skipping photo conversion on startup for now.\n", .{});

    // Initialize AuthContext
    var auth_ctx = try auth.AuthContext.init(allocator, io, "users.json");
    defer auth_ctx.deinit();

    // Start background image processing queue worker
    try processor.startQueueWorker(allocator, io);

    // 7. Start web server
    try server.startServer(init.io, auth_ctx, config);
}
