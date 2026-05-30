const std = @import("std");
const vips = @import("../src/vips.zig");
const db = @import("../src/db.zig");
const processor = @import("../src/processor.zig");

pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
        .async_limit = .unlimited,
    });
    defer threaded.deinit();
    const io = threaded.io();

    if (vips.vips_init("test_harness") != 0) {
        std.debug.print("Failed to init vips\n", .{});
        return;
    }
    defer vips.vips_shutdown();

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize test DB
    try db.init(allocator, io, "test_photos.db");
    defer db.deinit();

    // Initialize background worker
    try processor.startQueueWorker(allocator, io);

    // Prepare directories for the test job
    const orig_dir = "photos/admin/originals/2026/05";
    std.fs.cwd().makePath(orig_dir) catch {};

    // Copy scratch/test_video.mp4 to photos/admin/originals/2026/05/e749e749-e749-e749-e749-e749e749e749.mp4
    const uuid = "e749e749-e749-e749-e749-e749e749e749";
    const dest_path = "photos/admin/originals/2026/05/" ++ uuid ++ ".mp4";
    try std.fs.cwd().copyFile("scratch/test_video.mp4", std.fs.cwd(), dest_path, .{});
    std.debug.print("Copied test video to: {s}\n", .{dest_path});

    // Register job
    try processor.registerJob(
        uuid,
        "admin",
        "2026",
        "05",
        "mp4",
    );

    // Create and push the FileJob
    const job = try allocator.create(processor.FileJob);
    job.* = .{
        .allocator = allocator,
        .uuid = try allocator.dupe(u8, uuid),
        .username = try allocator.dupe(u8, "admin"),
        .filename = try allocator.dupe(u8, "test_video.mp4"),
        .year = try allocator.dupe(u8, "2026"),
        .month = try allocator.dupe(u8, "05"),
        .day = try allocator.dupe(u8, "30"),
        .upload_date = try allocator.dupe(u8, "2026-05-30 23:00:00"),
        .extension = try allocator.dupe(u8, "mp4"),
        .quality = 90,
        .t_start = @as(f64, @floatFromInt(vips.getWallMillis())),
    };

    processor.pushJob(job);
    std.debug.print("Pushed job to processing queue. Waiting for completion...\n", .{});

    // Sleep/wait a bit for the background job to finish
    var done = false;
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        std.time.sleep(1 * std.time.ns_per_s);
        // Check if DB record exists for the uuid
        const photos = db.getUserPhotos("admin", allocator) catch |err| {
            std.debug.print("Error getting user photos: {}\n", .{err});
            continue;
        };
        defer {
            for (photos) |r| {
                allocator.free(r.uuid);
                allocator.free(r.username);
                allocator.free(r.filename);
                allocator.free(r.extension);
                allocator.free(r.year);
                allocator.free(r.month);
                allocator.free(r.day);
                if (r.shooting_date) |sd| allocator.free(sd);
                allocator.free(r.upload_date);
            }
            allocator.free(photos);
        }

        for (photos) |record| {
            if (std.mem.eql(u8, record.uuid, uuid)) {
                std.debug.print("Success! Record found in DB:\n", .{});
                std.debug.print("UUID: {s}\n", .{record.uuid});
                std.debug.print("Filename: {s}\n", .{record.filename});
                std.debug.print("Shooting Date: {?s}\n", .{record.shooting_date});
                std.debug.print("Width: {?d}, Height: {?d}\n", .{record.width, record.height});
                done = true;
                break;
            }
        }
        if (done) break;
    }

    if (!done) {
        std.debug.print("Timeout or failure processing job.\n", .{});
    }
}
