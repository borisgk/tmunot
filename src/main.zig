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
    const config_paths = [_][]const u8{
        "/etc/tmunot/config.json",
        "config.json",
    };
    var config: config_mod.Config = undefined;
    var loaded = false;
    var path_to_free: ?[]const u8 = null;
    defer if (path_to_free) |p| allocator.free(p);

    for (config_paths) |path| {
        if (config_mod.loadConfig(allocator, io, path)) |cfg| {
            config = cfg;
            const dupe_path = try allocator.dupe(u8, path);
            path_to_free = dupe_path;
            config_mod.resolved_config_path = dupe_path;
            std.debug.print("Loaded config from: {s}\n", .{path});
            loaded = true;
            break;
        } else |err| {
            if (err == error.FileNotFound) {
                continue;
            }
            std.debug.print("Error loading config from {s}: {}\n", .{ path, err });
            return err;
        }
    }

    if (!loaded) {
        std.debug.print("Error: Configuration file config.json not found in /etc/tmunot/config.json or the current working directory.\n", .{});
        std.process.exit(1);
    }
    defer allocator.free(config.backend);
    defer allocator.free(config.input_directory);
    defer allocator.free(config.db_dir);
    defer allocator.free(config.originals_dir);
    defer allocator.free(config.previews_dir);
    defer allocator.free(config.thumbnails_dir);
    defer allocator.free(config.hover_previews_dir);
    defer {
        for (config.outputs) |out| {
            allocator.free(out.name);
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

    // 3. Start background job processor
    try processor.startQueueWorker(allocator, init.io, &config);

    try performOneTimeVideoMigration(allocator, init.io, &config);

    // 7. Start web server
    try server.startServer(init.io, auth_ctx, config);
}

fn performOneTimeVideoMigration(allocator: std.mem.Allocator, io: std.Io, config: *const config_mod.Config) !void {
    const marker_path = try std.fmt.allocPrint(allocator, "{s}/.tmunot_video_rotation_fixed", .{config.db_dir});
    defer allocator.free(marker_path);

    const cwd = std.Io.Dir.cwd();
    if (cwd.openFile(io, marker_path, .{})) |file| {
        file.close(io);
        return;
    } else |_| {}

    std.debug.print("Starting one-time video update to fix rotation...\n", .{});
    
    const users = try db.getUsers(allocator);
    defer {
        for (users) |u| {
            allocator.free(u.username);
            allocator.free(u.password_hash);
        }
        allocator.free(users);
    }

    var count: usize = 0;
    for (users) |user| {
        const photos = try db.getUserPhotos(user.username, allocator);
        defer {
            for (photos) |p| {
                allocator.free(p.uuid);
                allocator.free(p.username);
                allocator.free(p.filename);
                allocator.free(p.extension);
                allocator.free(p.year);
                allocator.free(p.month);
                allocator.free(p.day);
                if (p.shooting_date) |sd| allocator.free(sd);
                allocator.free(p.upload_date);
            }
            allocator.free(photos);
        }

        for (photos) |p| {
            if (std.ascii.eqlIgnoreCase(p.extension, "mp4") or std.ascii.eqlIgnoreCase(p.extension, "mov")) {
                const job = try allocator.create(processor.FileJob);
                job.* = processor.FileJob{
                    .allocator = allocator,
                    .uuid = try allocator.dupe(u8, p.uuid),
                    .username = try allocator.dupe(u8, p.username),
                    .year = try allocator.dupe(u8, p.year),
                    .month = try allocator.dupe(u8, p.month),
                    .day = try allocator.dupe(u8, p.day),
                    .filename = try allocator.dupe(u8, p.filename),
                    .extension = try allocator.dupe(u8, p.extension),
                    .upload_date = try allocator.dupe(u8, p.upload_date),
                    .quality = config.quality,
                    .t_start = vips.getWallMillis(),
                    .next = null,
                };
                processor.pushJob(job);
                count += 1;
            }
        }
    }

    if (cwd.createFile(io, marker_path, .{})) |marker_file| {
        marker_file.close(io);
    } else |err| {
        std.debug.print("Could not create marker file: {}\n", .{err});
    }

    std.debug.print("One-time video update dispatched {d} videos to the background queue.\n", .{count});
}
