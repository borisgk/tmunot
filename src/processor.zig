const std = @import("std");
const vips = @import("vips.zig");

pub const FileJob = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    buffer: []const u8,         // Memory buffer of original image
    uuid: []const u8,           // Photo UUID
    username: []const u8,       // Username of the owner
    year: []const u8,           // Chronological year
    month: []const u8,          // Chronological month
    extension: []const u8,      // Lowercase file extension
    quality: i32,
};

pub fn worker(job: *FileJob) void {
    const t_start = vips.getThreadCpuMillis();
    defer {
        job.allocator.free(job.buffer);
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

        // Recursively create target folder
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(job.io, target_dir) catch |err| {
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
            // First (largest) output: read from buffer
            const res = vips.vips_thumbnail_buffer(
                job.buffer.ptr,
                job.buffer.len,
                &next_img,
                @as(c_int, target.width),
                "height",
                @as(c_int, target.height),
                @as(?*anyopaque, null),
            );

            if (res != 0) {
                std.debug.print("Failed to read and resize image from buffer: {s}\n", .{vips.vips_error_buffer()});
                return;
            }

            // Copy to memory for cascading
            const mem_img = vips.vips_image_copy_memory(next_img);
            if (next_img) |img| vips.g_object_unref(img);
            next_img = mem_img;
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

            if (res != 0) {
                std.debug.print("Failed to scale image down for '{s}': {s}\n", .{target.name, vips.vips_error_buffer()});
                if (current_img) |img| vips.g_object_unref(img);
                return;
            }
        }

        const write_res = vips.vips_image_write_to_file(next_img, out_c.ptr, @as(?*anyopaque, null));

        if (write_res != 0) {
            std.debug.print("Failed to save image '{s}': {s}\n", .{ output_path, vips.vips_error_buffer() });
        } else {
            std.debug.print("[{s}] Resized: {s}.{s} -> {s}\n", .{ target.name, job.uuid, job.extension, output_path });
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
