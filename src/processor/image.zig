const std = @import("std");
const vips = @import("../vips.zig");
const logger = @import("../logger.zig");
const db = @import("../db.zig");
const exif = @import("../exif.zig");
const queue = @import("queue.zig");
const media = @import("media.zig");

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;

pub fn processImage(job: *queue.FileJob, orig_path_ptr: *[]u8, t_start: f64) !void {
    const io = queue.global_io orelse return error.NoGlobalIo;
    var orig_path = orig_path_ptr.*;

    // Read the original file into memory temporarily to extract EXIF in a closed scope
    const file_buf = blk: {
        const cwd = std.Io.Dir.cwd();
        var orig_file = cwd.openFile(io, orig_path, .{}) catch |err| {
            std.debug.print("Failed to open original file for metadata: {}\n", .{err});
            return error.FileOpenFailed;
        };
        defer orig_file.close(io);

        const file_size = (orig_file.stat(io) catch |err| {
            std.debug.print("Failed to stat original file: {}\n", .{err});
            return error.FileStatFailed;
        }).size;

        const buf = job.allocator.alloc(u8, @intCast(file_size)) catch |err| {
            std.debug.print("Failed to allocate file buffer: {}\n", .{err});
            return error.OutOfMemory;
        };
        errdefer job.allocator.free(buf);

        var file_reader = orig_file.reader(io, &.{});
        file_reader.interface.readSliceAll(buf) catch |err| {
            std.debug.print("Failed to read original file contents: {}\n", .{err});
            return error.FileReadFailed;
        };
        break :blk buf;
    };
    defer job.allocator.free(file_buf);

    // Extract EXIF data from RAM buffer
    const metadata = exif.extractExifFromBuffer(job.allocator, file_buf) catch |err| {
        std.debug.print("Failed to extract EXIF: {}\n", .{err});
        return error.ExifExtractionFailed;
    };
    defer if (metadata.shooting_date) |sd| job.allocator.free(sd);

    // If a shooting date exists, use it to organize folder paths and DB entries (Year/Month)
    if (metadata.shooting_date) |sd| {
        if (sd.len >= 10) {
            const shooting_year = sd[0..4];
            const shooting_month = sd[5..7];
            const shooting_day = sd[8..10];

            // Only move if it differs from the upload date
            if (!std.mem.eql(u8, shooting_year, job.year) or !std.mem.eql(u8, shooting_month, job.month) or !std.mem.eql(u8, shooting_day, job.day)) {
                // Construct new originals directory path
                const new_orig_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ queue.global_config.?.originals_dir, job.username, shooting_year, shooting_month }) catch |err| {
                    std.debug.print("Failed to format new original dir: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(new_orig_dir);

                // Create the target folder recursively
                media.makeDirPathSync(job.allocator, new_orig_dir) catch |err| {
                    std.debug.print("Failed to create folder '{s}': {}\n", .{ new_orig_dir, err });
                    return error.CreateDirFailed;
                };

                // New original path
                const new_orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.{s}", .{ new_orig_dir, job.uuid, job.extension }) catch |err| {
                    std.debug.print("Failed to format new original path: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(new_orig_path);

                // Move file using standard C rename
                const old_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{orig_path}, 0) catch |err| {
                    std.debug.print("Failed to format sentinel old path: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(old_path_c);

                const new_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{new_orig_path}, 0) catch |err| {
                    std.debug.print("Failed to format sentinel new path: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(new_path_c);

                if (rename(old_path_c.ptr, new_path_c.ptr) != 0) {
                    std.debug.print("Failed to rename original photo to shooting date path using C rename\n", .{});
                    return error.RenameFailed;
                }

                std.debug.print("Moved original from upload date path '{s}' to shooting date path '{s}'\n", .{ orig_path, new_orig_path });

                // Update job properties in memory so subsequent preview/thumbnail generation uses shooting date
                job.allocator.free(job.year);
                job.allocator.free(job.month);
                job.allocator.free(job.day);

                job.year = job.allocator.dupe(u8, shooting_year) catch |err| {
                    std.debug.print("Failed to duplicate shooting year: {}\n", .{err});
                    return error.OutOfMemory;
                };
                job.month = job.allocator.dupe(u8, shooting_month) catch |err| {
                    std.debug.print("Failed to duplicate shooting month: {}\n", .{err});
                    return error.OutOfMemory;
                };
                job.day = job.allocator.dupe(u8, shooting_day) catch |err| {
                    std.debug.print("Failed to duplicate shooting day: {}\n", .{err});
                    return error.OutOfMemory;
                };

                // Update orig_path in memory to point to the new shooting date original folder path
                job.allocator.free(orig_path);
                orig_path = job.allocator.dupe(u8, new_orig_path) catch |err| {
                    std.debug.print("Failed to duplicate new original path: {}\n", .{err});
                    return error.OutOfMemory;
                };
                orig_path_ptr.* = orig_path;
            }
        }
    }

    // Determine dimensions in RAM
    var width = metadata.width;
    var height = metadata.height;
    if (width == null or height == null) {
        const img = vips.vips_image_new_from_buffer(file_buf.ptr, file_buf.len, "", @as(?*anyopaque, null));
        if (img) |im| {
            width = vips.vips_image_get_width(im);
            height = vips.vips_image_get_height(im);
            vips.g_object_unref(im);
        }
    }

    // Write photo metadata first to satisfy FOREIGN KEY constraints
    const record = db.PhotoRecord{
        .uuid = job.uuid,
        .username = job.username,
        .filename = job.filename,
        .extension = job.extension,
        .year = job.year,
        .month = job.month,
        .day = job.day,
        .shooting_date = metadata.shooting_date,
        .upload_date = job.upload_date,
        .width = width,
        .height = height,
    };

    db.pushDbInsertPhoto(record) catch |err| {
        std.debug.print("Failed to queue photo insert: {}\n", .{err});
        return error.DbInsertFailed;
    };

    // Extract Full EXIF data for SQLite
    const full_exif_record = exif.extractFullExifFromBuffer(job.allocator, file_buf, job.uuid) catch |err| {
        std.debug.print("Failed to extract full EXIF: {}\n", .{err});
        return error.ExifExtractionFailed;
    };
    defer {
        @setEvalBranchQuota(10000);
        inline for (comptime std.meta.fieldNames(db.PhotoExifRecord)) |field_name| {
            if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                if (@field(full_exif_record, field_name)) |v| job.allocator.free(v);
            }
        }
        job.allocator.free(full_exif_record.uuid);
    }
    db.pushDbInsertPhotoExif(job.username, full_exif_record) catch |err| {
        std.debug.print("Failed to queue EXIF insert: {}\n", .{err});
    };

    const t_db = vips.getWallMillis();
    logger.logEvent(job.uuid, "database updated (bg)", t_start, t_db);

    var current_img: ?*vips.VipsImage = null;

    for (queue.global_config.?.outputs, 0..) |target, idx| {
        const base_dir = if (std.mem.eql(u8, target.name, "previews")) queue.global_config.?.previews_dir else queue.global_config.?.thumbnails_dir;
        const target_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ base_dir, job.username, job.year, job.month }) catch |err| {
            std.debug.print("Failed to format target directory: {}\n", .{err});
            continue;
        };
        defer job.allocator.free(target_dir);

        // Recursively create target folder using standard synchronous filesystem call
        media.makeDirPathSync(job.allocator, target_dir) catch |err| {
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
            // First (largest) output: resize from the buffer already in memory (avoids re-reading from disk)
            const res = vips.vips_thumbnail_buffer(
                file_buf.ptr,
                file_buf.len,
                &next_img,
                @as(c_int, target.target_width),
                "height",
                @as(c_int, target.target_height),
                "auto_rotate",
                @as(c_int, 1),
                @as(?*anyopaque, null),
            );
            const t1 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_thumbnail_buffer completed from memory", t_start, t1);

            if (res != 0) {
                std.debug.print("Failed to read and resize image from file: {s}\n", .{vips.vips_error_buffer()});
                return error.VipsThumbnailFailed;
            }

            // Copy to memory for cascading
            const mem_img = vips.vips_image_copy_memory(next_img);
            if (next_img) |img| vips.g_object_unref(img);
            next_img = mem_img;
            const t2 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_image_copy_memory completed", t_start, t2);
        } else {
            // Subsequent outputs: scale from the previous image in memory
            const res = vips.vips_thumbnail_image(
                current_img,
                &next_img,
                @as(c_int, target.target_width),
                "height",
                @as(c_int, target.target_height),
                "auto_rotate",
                @as(c_int, 1),
                @as(?*anyopaque, null),
            );
            const t1 = vips.getWallMillis();
            logger.logEvent(job.uuid, "vips_thumbnail_image completed", t_start, t1);

            if (res != 0) {
                std.debug.print("Failed to scale image down for '{s}': {s}\n", .{target.name, vips.vips_error_buffer()});
                if (current_img) |img| vips.g_object_unref(img);
                return error.VipsThumbnailFailed;
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
                logger.logEvent(job.uuid, "vips_image_write_to_file completed (previews)", t_start, t4);
                logger.logEvent(job.uuid, "preview created", t_start, t_created);
            } else if (std.mem.eql(u8, target.name, "thumbnails")) {
                logger.logEvent(job.uuid, "vips_image_write_to_file completed (thumbnails)", t_start, t4);
                logger.logEvent(job.uuid, "thumbnails created", t_start, t_created);
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
}
