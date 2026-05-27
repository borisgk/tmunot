const std = @import("std");
const vips = @import("vips.zig");
const logger = @import("logger.zig");

pub extern "c" fn usleep(useconds: c_uint) c_int;

pub const FileJob = struct {
    allocator: std.mem.Allocator,
    uuid: []const u8,           // Photo UUID
    username: []const u8,       // Username of the owner
    year: []const u8,           // Chronological year
    month: []const u8,          // Chronological month
    extension: []const u8,      // Lowercase file extension
    quality: i32,
    t_start: f64,
    next: ?*FileJob = null,
};

var job_queue_mutex: std.atomic.Mutex = .unlocked;
var job_queue_head: ?*FileJob = null;
var job_queue_tail: ?*FileJob = null;
var worker_thread: ?std.Thread = null;
var worker_should_exit: bool = false;

pub fn pushJob(job: *FileJob) void {
    while (!job_queue_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer job_queue_mutex.unlock();

    job.next = null;
    if (job_queue_tail) |tail| {
        tail.next = job;
        job_queue_tail = job;
    } else {
        job_queue_head = job;
        job_queue_tail = job;
    }
}

fn popJob() ?*FileJob {
    while (!job_queue_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer job_queue_mutex.unlock();

    if (job_queue_head) |head| {
        job_queue_head = head.next;
        if (job_queue_head == null) {
            job_queue_tail = null;
        }
        return head;
    }
    return null;
}

pub fn startQueueWorker() !void {
    if (worker_thread != null) return;
    worker_should_exit = false;
    worker_thread = try std.Thread.spawn(.{}, queueWorkerLoop, .{});
}

fn queueWorkerLoop() void {
    std.debug.print("Background image processing queue worker started.\n", .{});
    while (!worker_should_exit) {
        if (popJob()) |job| {
            processJob(job);
        } else {
            // Sleep for 20ms to avoid high CPU consumption
            _ = usleep(20 * 1000);
        }
    }
}

fn makeDirPathSync(allocator: std.mem.Allocator, target_dir: []const u8) !void {
    var it = std.mem.splitScalar(u8, target_dir, '/');
    var current_path = std.ArrayList(u8).empty;
    defer current_path.deinit(allocator);

    while (it.next()) |component| {
        if (component.len == 0) continue;
        if (current_path.items.len > 0) {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, component);

        const path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{current_path.items}, 0);
        defer allocator.free(path_c);

        _ = vips.mkdir(path_c.ptr, 0o777);
    }
}

fn processJob(job: *FileJob) void {
    const t_start = vips.getThreadCpuMillis();
    defer {
        job.allocator.free(job.uuid);
        job.allocator.free(job.username);
        job.allocator.free(job.year);
        job.allocator.free(job.month);
        job.allocator.free(job.extension);
        job.allocator.destroy(job);
    }

    const TargetSize = struct {
        name: []const u8,
        width: i32,
        height: i32,
    };

    const targets = [_]TargetSize{
        .{ .name = "previews", .width = 1200, .height = 1200 },
        .{ .name = "thumbnails", .width = 600, .height = 600 },
    };

    var current_img: ?*vips.VipsImage = null;

    for (targets, 0..) |target, idx| {
        // Construct target directory path: photos/<username>/<target.name>/<year>/<month>
        const target_dir = std.fmt.allocPrint(job.allocator, "photos/{s}/{s}/{s}/{s}", .{ job.username, target.name, job.year, job.month }) catch |err| {
            std.debug.print("Failed to format target directory: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(target_dir);

        // Recursively create target folder using standard synchronous filesystem call
        makeDirPathSync(job.allocator, target_dir) catch |err| {
            std.debug.print("Failed to recursively create target path '{s}': {}\n", .{ target_dir, err });
            continue;
        };

        // Construct final file path: photos/<username>/<target.name>/<year>/<month>/<uuid>.<ext>
        const output_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.{s}", .{ target_dir, job.uuid, job.extension }) catch |err| {
            std.debug.print("Failed to format output path: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(output_path);

        // Quality and save options formatting: filepath[Q=90]
        const out_c = std.fmt.allocPrintSentinel(job.allocator, "{s}[Q={d}]", .{ output_path, job.quality }, 0) catch |err| {
            std.debug.print("Failed to format output path options: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(out_c);

        var next_img: ?*vips.VipsImage = null;

        if (idx == 0) {
            // Construct original chronological path: photos/<username>/originals/<year>/<month>/<uuid>.<ext>
            const orig_path = std.fmt.allocPrint(job.allocator, "photos/{s}/originals/{s}/{s}/{s}.{s}", .{
                job.username, job.year, job.month, job.uuid, job.extension
            }) catch |err| {
                std.debug.print("Failed to format original image path: {}\n", .{err});
                return;
            };
            defer job.allocator.free(orig_path);

            const orig_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{orig_path}, 0) catch |err| {
                std.debug.print("Failed to format original image path sentinel: {}\n", .{err});
                return;
            };
            defer job.allocator.free(orig_path_c);

            // First (largest) output: read directly from the original file saved on disk
            const res = vips.vips_thumbnail(
                orig_path_c.ptr,
                &next_img,
                @as(c_int, target.width),
                "height",
                @as(c_int, target.height),
                @as(?*anyopaque, null),
            );
            const t1 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_thumbnail completed from file", job.t_start, t1);

            if (res != 0) {
                std.debug.print("Failed to read and resize image from file: {s}\n", .{vips.vips_error_buffer()});
                return;
            }

            // Copy to memory for cascading
            const mem_img = vips.vips_image_copy_memory(next_img);
            if (next_img) |img| vips.g_object_unref(img);
            next_img = mem_img;
            const t2 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_image_copy_memory completed", job.t_start, t2);
        } else {
            // Subsequent outputs: scale from the previous image in memory
            const res = vips.vips_thumbnail_image(
                current_img,
                &next_img,
                @as(c_int, target.width),
                "height",
                @as(c_int, target.height),
                @as(?*anyopaque, null),
            );
            const t1 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_thumbnail_image completed", job.t_start, t1);

            if (res != 0) {
                std.debug.print("Failed to scale image down for '{s}': {s}\n", .{target.name, vips.vips_error_buffer()});
                if (current_img) |img| vips.g_object_unref(img);
                return;
            }
        }

        const write_res = vips.vips_image_write_to_file(next_img, out_c.ptr, @as(?*anyopaque, null));
        const t4 = vips.getWallMillis();

        if (write_res != 0) {
            std.debug.print("Failed to save image '{s}': {s}\n", .{ output_path, vips.vips_error_buffer() });
        } else {
            std.debug.print("[{s}] Resized: {s}.{s} -> {s}\n", .{ target.name, job.uuid, job.extension, output_path });
            const t_created = vips.getWallMillis();
            if (std.mem.eql(u8, target.name, "previews")) {
                logger.logEvent(job.uuid, "vips_image_write_to_file completed (previews)", job.t_start, t4);
                logger.logEvent(job.uuid, "preview created", job.t_start, t_created);
            } else if (std.mem.eql(u8, target.name, "thumbnails")) {
                logger.logEvent(job.uuid, "vips_image_write_to_file completed (thumbnails)", job.t_start, t4);
                logger.logEvent(job.uuid, "thumbnails created", job.t_start, t_created);
            }
        }

        if (current_img) |img| {
            vips.g_object_unref(img);
        }
        current_img = next_img;
    }

    if (current_img) |img| {
        vips.g_object_unref(img);
    }

    const elapsed_ms = vips.getThreadCpuMillis() - t_start;
    std.debug.print("Finished background processing '{s}.{s}' in {d:.2} CPU ms\n", .{ job.uuid, job.extension, elapsed_ms });
}

