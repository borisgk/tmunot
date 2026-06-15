const std = @import("std");
const vips = @import("../vips.zig");

const db = @import("../db.zig");
const video_meta = @import("../video_meta.zig");
const queue = @import("queue.zig");
const media = @import("media.zig");

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;
extern "c" fn unlink(pathname: [*c]const u8) c_int;

const FfprobeStream = struct {
    width: ?i32 = null,
    height: ?i32 = null,
    side_data_list: ?[]struct {
        // ffprobe outputs rotation as a float (e.g. -90.000000) derived from display matrix
        rotation: ?f64 = null,
    } = null,
    tags: ?struct {
        // Android devices often store rotation in stream tags instead of side_data
        rotate: ?[]const u8 = null,
    } = null,
};
const FfprobeFormat = struct {
    tags: ?struct {
        creation_time: ?[]const u8 = null,
    } = null,
};
const FfprobeResult = struct {
    streams: ?[]FfprobeStream = null,
    format: ?FfprobeFormat = null,
};

pub fn processVideo(job: *queue.FileJob, orig_path_ptr: *[]u8) !void {
    const io = queue.global_io orelse return error.NoGlobalIo;
    var orig_path = orig_path_ptr.*;

    var shooting_date_opt: ?[]const u8 = null;
    var width: ?i32 = null;
    var height: ?i32 = null;
    var rot: i32 = 0;

    // 1. Run ffprobe to get metadata
    // Use -show_streams -show_format so that side_data_list includes the derived
    // `rotation` integer field. With -show_entries stream_side_data=displaymatrix,
    // ffprobe only outputs the raw matrix bytes, not the computed rotation value.
    const ffprobe_res = std.process.run(job.allocator, io, .{
        .argv = &[_][]const u8{
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_streams", "-show_format",
            "-of", "json", orig_path
        },
    }) catch |err| blk: {
        std.debug.print("Failed to run ffprobe: {}\n", .{err});
        break :blk null;
    };

    if (ffprobe_res) |res| {
        defer {
            job.allocator.free(res.stdout);
            job.allocator.free(res.stderr);
        }

        if (res.term == .exited and res.term.exited == 0) {
            const parsed = std.json.parseFromSlice(FfprobeResult, job.allocator, res.stdout, .{ .ignore_unknown_fields = true }) catch |err| blk: {
                std.debug.print("Failed to parse ffprobe json: {}\n", .{err});
                break :blk null;
            };
            if (parsed) |p| {
                defer p.deinit();
                const val = p.value;
                if (val.streams) |streams| {
                    if (streams.len > 0) {
                        var w = streams[0].width orelse 640;
                        var h = streams[0].height orelse 480;
                        // Primary: rotation from display matrix side_data
                        if (streams[0].side_data_list) |sdl| {
                            if (sdl.len > 0) {
                                if (sdl[0].rotation) |r| {
                                    rot = @intFromFloat(r);
                                }
                            }
                        }
                        // Fallback: stream tags (common on Android devices)
                        if (rot == 0) {
                            if (streams[0].tags) |tags| {
                                if (tags.rotate) |rotate_str| {
                                    rot = std.fmt.parseInt(i32, rotate_str, 10) catch 0;
                                }
                            }
                        }
                        if (rot == 90 or rot == -90 or rot == 270 or rot == -270) {
                            const temp = w;
                            w = h;
                            h = temp;
                        }
                        width = w;
                        height = h;
                    }
                }

                if (val.format) |fmt| {
                    if (fmt.tags) |tags| {
                        if (tags.creation_time) |ct| {
                            if (ct.len >= 19) {
                                const date_buf = job.allocator.alloc(u8, 19) catch null;
                                if (date_buf) |db_slice| {
                                    @memcpy(db_slice[0..10], ct[0..10]);
                                    db_slice[10] = ' ';
                                    @memcpy(db_slice[11..19], ct[11..19]);
                                    shooting_date_opt = db_slice;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // If a shooting date exists, organize folder paths and DB entries chronologically
    if (shooting_date_opt) |sd| {
        if (sd.len >= 10) {
            const shooting_year = sd[0..4];
            const shooting_month = sd[5..7];
            const shooting_day = sd[8..10];

            if (!std.mem.eql(u8, shooting_year, job.year) or !std.mem.eql(u8, shooting_month, job.month) or !std.mem.eql(u8, shooting_day, job.day)) {
                const new_orig_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ queue.global_config.?.originals_dir, job.username, shooting_year, shooting_month }) catch |err| {
                    std.debug.print("Failed to format new original dir: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(new_orig_dir);

                media.makeDirPathSync(job.allocator, new_orig_dir) catch |err| {
                    std.debug.print("Failed to create folder '{s}': {}\n", .{ new_orig_dir, err });
                    return error.CreateDirFailed;
                };

                const new_orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.{s}", .{ new_orig_dir, job.uuid, job.extension }) catch |err| {
                    std.debug.print("Failed to format new original path: {}\n", .{err});
                    return error.FormattingFailed;
                };
                defer job.allocator.free(new_orig_path);

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
                    std.debug.print("Failed to rename original video to shooting date path using C rename\n", .{});
                    return error.RenameFailed;
                }

                std.debug.print("Moved original video from upload date path '{s}' to shooting date path '{s}'\n", .{ orig_path, new_orig_path });

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

                job.allocator.free(orig_path);
                orig_path = job.allocator.dupe(u8, new_orig_path) catch |err| {
                    std.debug.print("Failed to duplicate new original path: {}\n", .{err});
                    return error.OutOfMemory;
                };
                orig_path_ptr.* = orig_path;
            }
        }
    }

    // 2. Transcode 3-second looping silent hover preview (hover_previews/YYYY/MM/<uuid>.mp4)
    const hover_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ queue.global_config.?.hover_previews_dir, job.username, job.year, job.month }) catch |err| {
        std.debug.print("Failed to format hover previews dir: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(hover_dir);

    media.makeDirPathSync(job.allocator, hover_dir) catch |err| {
        std.debug.print("Failed to create hover folder '{s}': {}\n", .{ hover_dir, err });
        return error.CreateDirFailed;
    };

    const hover_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.mp4", .{ hover_dir, job.uuid }) catch |err| {
        std.debug.print("Failed to format hover path: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(hover_path);

    std.debug.print("Generating silent hover preview and thumbnail for: {s}.{s} (rot={d})\n", .{job.uuid, job.extension, rot});

    // ffmpeg applies rotation automatically without -noautorotate.
    // Scale to max 640px on the longer side while preserving aspect ratio.
    // For portrait video (|rot|==90/270): height is longer, limit by height.
    // For landscape or no rotation: width is longer, limit by width.
    const is_portrait = rot == 90 or rot == -90 or rot == 270 or rot == -270;
    const hover_vf: []const u8 = if (is_portrait) "scale=-2:'min(640,ih)'" else "scale='min(640,iw)':-2";

    const hover_res = std.process.run(job.allocator, io, .{
        .argv = &[_][]const u8{
            "ffmpeg", "-y", "-i", orig_path,
            "-t", "3",
            "-an", "-c:v", "libsvtav1", "-pix_fmt", "yuv420p10le", "-preset", "12", "-crf", "35",
            "-vf", hover_vf,
            "-movflags", "+faststart", hover_path
        },
    }) catch |err| {
        std.debug.print("Failed to run ffmpeg for hover preview: {}\n", .{err});
        return error.FfmpegFailed;
    };
    defer {
        job.allocator.free(hover_res.stdout);
        job.allocator.free(hover_res.stderr);
    }
    if (hover_res.term != .exited or hover_res.term.exited != 0) {
        std.debug.print("ffmpeg hover preview failed for {s}: {s}\n", .{job.uuid, hover_res.stderr});
    }

    // 4. Extract single static frame at 00:00:02
    const temp_frame_path = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}/{s}_frame.jpg", .{ queue.global_config.?.originals_dir, job.username, job.year, job.month, job.uuid }) catch |err| {
        std.debug.print("Failed to format temp frame path: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(temp_frame_path);

    const temp_frame_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{temp_frame_path}, 0) catch |err| {
        std.debug.print("Failed to format temp frame path sentinel: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer {
        _ = unlink(temp_frame_path_c.ptr);
        job.allocator.free(temp_frame_path_c);
    }

    const frame_res = std.process.run(job.allocator, io, .{
        .argv = &[_][]const u8{
            // No -noautorotate: ffmpeg auto-rotates based on display matrix metadata.
            // This ensures the extracted frame is correctly oriented (portrait for portrait videos).
            "ffmpeg", "-y", "-i", orig_path,
            "-vframes", "1", "-q:v", "2",
            temp_frame_path
        },
    }) catch |err| {
        std.debug.print("Failed to run ffmpeg frame extraction: {}\n", .{err});
        return error.FfmpegFailed;
    };
    defer {
        job.allocator.free(frame_res.stdout);
        job.allocator.free(frame_res.stderr);
    }

    if (frame_res.term != .exited or frame_res.term.exited != 0) {
        std.debug.print("ffmpeg frame extraction failed for {s}: {s}\n", .{job.uuid, frame_res.stderr});
        return error.FfmpegFrameFailed;
    }

    // 5. Build static thumbnails using libvips from the extracted frame
    const target_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ queue.global_config.?.thumbnails_dir, job.username, job.year, job.month }) catch |err| {
        std.debug.print("Failed to format thumbnails directory: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(target_dir);

    media.makeDirPathSync(job.allocator, target_dir) catch |err| {
        std.debug.print("Failed to recursively create thumbnails path '{s}': {}\n", .{ target_dir, err });
        return error.CreateDirFailed;
    };

    const output_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.jpg", .{ target_dir, job.uuid }) catch |err| {
        std.debug.print("Failed to format output path: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(output_path);

    const out_c = std.fmt.allocPrintSentinel(job.allocator, "{s}[Q={d}]", .{ output_path, job.quality }, 0) catch |err| {
        std.debug.print("Failed to format output path options: {}\n", .{err});
        return error.FormattingFailed;
    };
    defer job.allocator.free(out_c);

    var next_img: ?*vips.VipsImage = null;

    const thumb_res = vips.vips_thumbnail(
        temp_frame_path_c.ptr,
        &next_img,
        @as(c_int, 600),
        "height",
        @as(c_int, 600),
        "auto_rotate",
        @as(c_int, 1),
        @as(?*anyopaque, null),
    );
    if (thumb_res != 0) {
        std.debug.print("Failed to generate thumbnail for video {s}: {s}\n", .{job.uuid, vips.vips_error_buffer()});
        return error.VipsThumbnailFailed;
    }
    std.debug.print("Thumbnail generated: {s}\n", .{output_path});
    defer if (next_img) |img| vips.g_object_unref(img);

    const write_res = vips.vips_image_write_to_file(next_img, out_c.ptr, @as(?*anyopaque, null));
    if (write_res != 0) {
        std.debug.print("Failed to save video thumbnail: {s}\n", .{vips.vips_error_buffer()});
        return error.VipsWriteFailed;
    }

    // 6. Write video metadata records into SQLite
    const record = db.PhotoRecord{
        .uuid = job.uuid,
        .username = job.username,
        .filename = job.filename,
        .extension = job.extension,
        .year = job.year,
        .month = job.month,
        .day = job.day,
        .shooting_date = shooting_date_opt,
        .upload_date = job.upload_date,
        .width = width,
        .height = height,
    };

    db.pushDbInsertPhoto(record) catch |err| {
        std.debug.print("Failed to queue video photo insert: {}\n", .{err});
        return error.DbInsertFailed;
    };

    // Extract and insert video metadata
    const video_record = video_meta.extractVideoMetadata(job.allocator, io, orig_path, job.uuid) catch |err| {
        std.debug.print("Failed to extract video metadata: {}\n", .{err});
        return error.MetadataExtractionFailed;
    };
    defer {
        @setEvalBranchQuota(10000);
        inline for (comptime std.meta.fieldNames(db.VideoMetadataRecord)) |field_name| {
            if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                if (@field(video_record, field_name)) |v| job.allocator.free(v);
            }
        }
        job.allocator.free(video_record.uuid);
    }
    db.pushDbInsertVideoMetadata(job.username, video_record) catch |err| {
        std.debug.print("Failed to queue video metadata insert: {}\n", .{err});
    };
}
