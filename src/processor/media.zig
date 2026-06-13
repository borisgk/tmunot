const std = @import("std");
const vips = @import("../vips.zig");
const logger = @import("../logger.zig");

const queue = @import("queue.zig");
const sse = @import("sse.zig");

const processor_video = @import("video.zig");
const processor_image = @import("image.zig");

pub fn makeDirPathSync(allocator: std.mem.Allocator, target_dir: []const u8) !void {

    if (target_dir.len == 0) return;

    var it = std.mem.splitScalar(u8, target_dir, '/');
    var current_path = std.ArrayList(u8).empty;
    defer current_path.deinit(allocator);

    if (target_dir[0] == '/') {
        try current_path.append(allocator, '/');
    }

    while (it.next()) |component| {
        if (component.len == 0) continue;
        if (current_path.items.len > 0 and current_path.items[current_path.items.len - 1] != '/') {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, component);

        const path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{current_path.items}, 0);
        defer allocator.free(path_c);

        _ = vips.mkdir(path_c.ptr, 0o777);
    }
}

pub fn processJob(job: *queue.FileJob) void {
    const t_start = vips.getThreadCpuMillis();
    var is_error = true;
    defer {
        queue.removeJob(job.uuid);
        sse.broadcastSseEvent(job.uuid, if (is_error) "error" else "completed", job.extension, job.username);

        job.allocator.free(job.uuid);
        job.allocator.free(job.username);
        job.allocator.free(job.filename);
        job.allocator.free(job.year);
        job.allocator.free(job.month);
        job.allocator.free(job.day);
        job.allocator.free(job.upload_date);
        job.allocator.free(job.extension);
        job.allocator.destroy(job);
    }

    // 1. Mark status as processing in registry
    queue.updateJobStatus(job.uuid, .processing);


    // Formulate chronological original path
    var orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}/{s}.{s}", .{
        queue.global_config.?.originals_dir, job.username, job.year, job.month, job.uuid, job.extension
    }) catch |err| {
        std.debug.print("Failed to format original path for DB: {}\n", .{err});
        return;
    };
    defer job.allocator.free(orig_path);

    const is_video = std.mem.eql(u8, job.extension, "mp4") or
                     std.mem.eql(u8, job.extension, "mov") or
                     std.mem.eql(u8, job.extension, "m4v") or
                     std.mem.eql(u8, job.extension, "webm") or
                     std.mem.eql(u8, job.extension, "avi");

    if (is_video) {
        processor_video.processVideo(job, &orig_path) catch |err| {
            std.debug.print("Video processing failed: {}\n", .{err});
            return;
        };
        is_error = false;
    } else {
        processor_image.processImage(job, &orig_path, t_start) catch |err| {
            std.debug.print("Image processing failed: {}\n", .{err});
            return;
        };
        is_error = false;
    }

    const elapsed_ms = vips.getThreadCpuMillis() - t_start;
    std.debug.print("Finished background processing '{s}.{s}' in {d:.2} CPU ms\n", .{ job.uuid, job.extension, elapsed_ms });
}
