const std = @import("std");
const config = @import("config.zig");
const vips = @import("vips.zig");

pub const FileJob = struct {
    allocator: std.mem.Allocator,
    input_path: []const u8,
    filename: []const u8,
    outputs: []config.OutputConfig,
    quality: i32,
};

pub fn worker(job: *FileJob) void {
    const t_start = vips.getThreadCpuMillis();
    defer {
        job.allocator.free(job.input_path);
        job.allocator.free(job.filename);
        job.allocator.destroy(job);
    }

    const in_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{job.input_path}, 0) catch |err| {
        std.debug.print("Failed to convert input path '{s}' to C string: {}\n", .{ job.input_path, err });
        return;
    };
    defer job.allocator.free(in_c);

    var current_img: ?*vips.VipsImage = null;

    for (job.outputs, 0..) |out, idx| {
        const output_path = std.fs.path.join(job.allocator, &.{ out.directory, job.filename }) catch |err| {
            std.debug.print("Failed to join output path: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(output_path);

        const out_c = std.fmt.allocPrintSentinel(job.allocator, "{s}[Q={d}]", .{ output_path, job.quality }, 0) catch |err| {
            std.debug.print("Failed to format output path options: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(out_c);

        var next_img: ?*vips.VipsImage = null;

        if (idx == 0) {
            // First (largest) output: read from file
            const res = vips.vips_thumbnail(
                in_c.ptr,
                &next_img,
                @as(c_int, out.target_width),
                "height",
                @as(c_int, out.target_height),
                @as(?*anyopaque, null)
            );
            if (res != 0) {
                std.debug.print("Failed to read and resize image '{s}': {s}\n", .{ job.input_path, vips.vips_error_buffer() });
                return;
            }
            
            // Copy to memory so we can read from it multiple times (for saving and for subsequent cascading)
            const mem_img = vips.vips_image_copy_memory(next_img);
            if (next_img) |img| vips.g_object_unref(img);
            next_img = mem_img;
        } else {
            // Subsequent outputs: scale from the previous image in memory
            const res = vips.vips_thumbnail_image(
                current_img,
                &next_img,
                @as(c_int, out.target_width),
                "height",
                @as(c_int, out.target_height),
                @as(?*anyopaque, null)
            );
            if (res != 0) {
                std.debug.print("Failed to scale image down for '{s}': {s}\n", .{ out.name, vips.vips_error_buffer() });
                if (current_img) |img| vips.g_object_unref(img);
                return;
            }
        }

        const write_res = vips.vips_image_write_to_file(next_img, out_c.ptr, @as(?*anyopaque, null));
        
        if (write_res != 0) {
            std.debug.print("Failed to save image '{s}': {s}\n", .{ output_path, vips.vips_error_buffer() });
        } else {
            std.debug.print("[{s}] Resized: {s} -> {s}\n", .{ out.name, job.input_path, output_path });
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
    std.debug.print("Finished processing '{s}' (all sizes) in {d:.2} CPU ms\n", .{job.filename, elapsed_ms});
}
