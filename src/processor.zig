const std = @import("std");
const vips = @import("vips.zig");
const logger = @import("logger.zig");
const db = @import("db.zig");
const exif = @import("exif.zig");
const config_mod = @import("config.zig");

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;
extern "c" fn unlink(pathname: [*c]const u8) c_int;

const FfprobeStream = struct {
    width: ?i32 = null,
    height: ?i32 = null,
    side_data_list: ?[]struct {
        rotation: ?i32 = null,
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

pub const FileJob = struct {
    allocator: std.mem.Allocator,
    uuid: []const u8,           // Photo UUID
    username: []const u8,       // Username of the owner
    filename: []const u8,       // Original filename
    year: []const u8,           // Chronological year
    month: []const u8,          // Chronological month
    day: []const u8,            // Chronological day
    upload_date: []const u8,    // Date when uploaded
    extension: []const u8,      // Lowercase file extension
    quality: i32,
    t_start: f64,
    next: ?*FileJob = null,
};

// Queue state
var job_queue_mutex: std.atomic.Mutex = .unlocked;
var job_queue_head: ?*FileJob = null;
var job_queue_tail: ?*FileJob = null;
var job_queue_sem = std.Io.Semaphore{};
var worker_threads: ?[]std.Thread = null;
var worker_should_exit: bool = false;
var global_io: ?std.Io = null;
var global_config: ?*const config_mod.Config = null;

// Registry State
pub const JobStatus = enum {
    pending,
    processing,
};

pub const ActiveJob = struct {
    username: []const u8,
    year: []const u8,
    month: []const u8,
    extension: []const u8,
    status: JobStatus,
};

var registry_mutex: std.atomic.Mutex = .unlocked;
var active_jobs: ?std.StringHashMap(ActiveJob) = null;
var registry_allocator: ?std.mem.Allocator = null;

pub fn initRegistry(allocator: std.mem.Allocator) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs == null) {
        active_jobs = std.StringHashMap(ActiveJob).init(allocator);
        registry_allocator = allocator;
    }
}

pub fn registerJob(uuid: []const u8, username: []const u8, year: []const u8, month: []const u8, extension: []const u8) !void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        const alloc = registry_allocator orelse return error.RegistryNotInitialized;
        const job = ActiveJob{
            .username = try alloc.dupe(u8, username),
            .year = try alloc.dupe(u8, year),
            .month = try alloc.dupe(u8, month),
            .extension = try alloc.dupe(u8, extension),
            .status = .pending,
        };
        const dupe_uuid = try alloc.dupe(u8, uuid);
        try map.put(dupe_uuid, job);
    }
}

pub fn updateJobStatus(uuid: []const u8, status: JobStatus) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        if (map.getPtr(uuid)) |job| {
            job.status = status;
        }
    }
}

pub fn removeJob(uuid: []const u8) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        if (map.fetchRemove(uuid)) |kv| {
            const alloc = registry_allocator orelse return;
            alloc.free(kv.key);
            alloc.free(kv.value.username);
            alloc.free(kv.value.year);
            alloc.free(kv.value.month);
            alloc.free(kv.value.extension);
        }
    }
}

pub fn getActiveJob(uuid: []const u8, allocator: std.mem.Allocator) !?ActiveJob {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |map| {
        if (map.get(uuid)) |job| {
            return ActiveJob{
                .username = try allocator.dupe(u8, job.username),
                .year = try allocator.dupe(u8, job.year),
                .month = try allocator.dupe(u8, job.month),
                .extension = try allocator.dupe(u8, job.extension),
                .status = job.status,
            };
        }
    }
    return null;
}

pub fn isJobActive(uuid: []const u8) bool {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |map| {
        return map.contains(uuid);
    }
    return false;
}

// SSE Connection state
pub const SseClient = struct {
    stream: std.Io.net.Stream,
    username: []const u8,
};

var sse_mutex: std.atomic.Mutex = .unlocked;
var sse_clients = std.ArrayList(SseClient).empty;
var sse_allocator: ?std.mem.Allocator = null;

pub fn addSseClient(stream: std.Io.net.Stream, username: []const u8) !void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const alloc = sse_allocator orelse return error.RegistryNotInitialized;
    try sse_clients.append(alloc, .{
        .stream = stream,
        .username = try alloc.dupe(u8, username),
    });
    std.debug.print("Added SSE client for user: {s}, count: {d}\n", .{ username, sse_clients.items.len });
}

pub fn removeSseClient(stream: std.Io.net.Stream) void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const alloc = sse_allocator orelse return;
    var i: usize = 0;
    while (i < sse_clients.items.len) {
        if (sse_clients.items[i].stream.socket.handle == stream.socket.handle) {
            const client = sse_clients.orderedRemove(i);
            alloc.free(client.username);
            std.debug.print("Removed SSE client, remaining count: {d}\n", .{ sse_clients.items.len });
        } else {
            i += 1;
        }
    }
}

pub fn broadcastSseEvent(uuid: []const u8, status: []const u8, ext: []const u8, target_user: []const u8) void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const io = global_io orelse return;
    const alloc = sse_allocator orelse return;

    const payload = std.fmt.allocPrint(alloc,
        "data: {{\"uuid\":\"{s}\",\"status\":\"{s}\",\"ext\":\"{s}\"}}\n\n",
        .{ uuid, status, ext }
    ) catch return;
    defer alloc.free(payload);

    var i: usize = 0;
    while (i < sse_clients.items.len) {
        const client = sse_clients.items[i];
        if (std.mem.eql(u8, client.username, target_user)) {
            var write_buf: [256]u8 = undefined;
            var writer = client.stream.writer(io, &write_buf);
            writer.interface.writeAll(payload) catch {
                const removed = sse_clients.orderedRemove(i);
                alloc.free(removed.username);
                removed.stream.close(io);
                continue;
            };
            writer.interface.flush() catch {
                const removed = sse_clients.orderedRemove(i);
                alloc.free(removed.username);
                removed.stream.close(io);
                continue;
            };
        }
        i += 1;
    }
}

pub fn writeKeepAlive(stream: std.Io.net.Stream) !bool {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const io = global_io orelse return false;
    var write_buf: [256]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    writer.interface.writeAll(": keep-alive\n\n") catch {
        return false;
    };
    writer.interface.flush() catch {
        return false;
    };
    return true;
}

pub fn pushJob(job: *FileJob) void {
    while (!job_queue_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }

    job.next = null;
    if (job_queue_tail) |tail| {
        tail.next = job;
        job_queue_tail = job;
    } else {
        job_queue_head = job;
        job_queue_tail = job;
    }
    job_queue_mutex.unlock();

    if (global_io) |io| {
        job_queue_sem.post(io);
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

pub fn startQueueWorker(allocator: std.mem.Allocator, io: std.Io, config: *const config_mod.Config) !void {
    if (worker_threads != null) return;
    worker_should_exit = false;
    global_io = io;
    global_config = config;

    // Initialize registry and sse allocator
    initRegistry(allocator);
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    sse_allocator = allocator;
    sse_clients = std.ArrayList(SseClient).empty;
    sse_mutex.unlock();

    const worker_count = 2; // concurrent worker threads
    var threads = try allocator.alloc(std.Thread, worker_count);
    for (0..worker_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, queueWorkerLoop, .{});
    }
    worker_threads = threads;
}

fn queueWorkerLoop() void {
    std.debug.print("Background image processing queue worker started.\n", .{});
    const io = global_io.?;
    while (!worker_should_exit) {
        job_queue_sem.waitUncancelable(io);
        if (worker_should_exit) break;

        if (popJob()) |job| {
            processJob(job);
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
    var is_error = true;
    defer {
        removeJob(job.uuid);
        broadcastSseEvent(job.uuid, if (is_error) "error" else "completed", job.extension, job.username);

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
    updateJobStatus(job.uuid, .processing);

    const io = global_io orelse return;

    // Formulate chronological original path
    var orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}/{s}.{s}", .{
        global_config.?.originals_dir, job.username, job.year, job.month, job.uuid, job.extension
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
        var shooting_date_opt: ?[]const u8 = null;
        var width: ?i32 = null;
        var height: ?i32 = null;

        // 1. Run ffprobe to get metadata
        const ffprobe_res = std.process.run(job.allocator, io, .{
            .argv = &[_][]const u8{
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height:stream_side_data=displaymatrix:format_tags=creation_time",
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
                            var rot: i32 = 0;
                            if (streams[0].side_data_list) |sdl| {
                                if (sdl.len > 0) {
                                    rot = sdl[0].rotation orelse 0;
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
                    const new_orig_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ global_config.?.originals_dir, job.username, shooting_year, shooting_month }) catch |err| {
                        std.debug.print("Failed to format new original dir: {}\n", .{err});
                        return;
                    };
                    defer job.allocator.free(new_orig_dir);

                    makeDirPathSync(job.allocator, new_orig_dir) catch |err| {
                        std.debug.print("Failed to create folder '{s}': {}\n", .{ new_orig_dir, err });
                        return;
                    };

                    const new_orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.{s}", .{ new_orig_dir, job.uuid, job.extension }) catch |err| {
                        std.debug.print("Failed to format new original path: {}\n", .{err});
                        return;
                    };
                    defer job.allocator.free(new_orig_path);

                    const old_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{orig_path}, 0) catch |err| {
                        std.debug.print("Failed to format sentinel old path: {}\n", .{err});
                        return;
                    };
                    defer job.allocator.free(old_path_c);

                    const new_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{new_orig_path}, 0) catch |err| {
                        std.debug.print("Failed to format sentinel new path: {}\n", .{err});
                        return;
                    };
                    defer job.allocator.free(new_path_c);

                    if (rename(old_path_c.ptr, new_path_c.ptr) != 0) {
                        std.debug.print("Failed to rename original video to shooting date path using C rename\n", .{});
                        return;
                    }

                    std.debug.print("Moved original video from upload date path '{s}' to shooting date path '{s}'\n", .{ orig_path, new_orig_path });

                    job.allocator.free(job.year);
                    job.allocator.free(job.month);
                    job.allocator.free(job.day);

                    job.year = job.allocator.dupe(u8, shooting_year) catch |err| {
                        std.debug.print("Failed to duplicate shooting year: {}\n", .{err});
                        return;
                    };
                    job.month = job.allocator.dupe(u8, shooting_month) catch |err| {
                        std.debug.print("Failed to duplicate shooting month: {}\n", .{err});
                        return;
                    };
                    job.day = job.allocator.dupe(u8, shooting_day) catch |err| {
                        std.debug.print("Failed to duplicate shooting day: {}\n", .{err});
                        return;
                    };

                    job.allocator.free(orig_path);
                    orig_path = job.allocator.dupe(u8, new_orig_path) catch |err| {
                        std.debug.print("Failed to duplicate new original path: {}\n", .{err});
                        return;
                    };
                }
            }
        }

        // 2. Transcode 3-second looping silent hover preview (hover_previews/YYYY/MM/<uuid>.mp4)
        const hover_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ global_config.?.hover_previews_dir, job.username, job.year, job.month }) catch |err| {
            std.debug.print("Failed to format hover previews dir: {}\n", .{err});
            return;
        };
        defer job.allocator.free(hover_dir);

        makeDirPathSync(job.allocator, hover_dir) catch |err| {
            std.debug.print("Failed to create hover folder '{s}': {}\n", .{ hover_dir, err });
            return;
        };

        const hover_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.mp4", .{ hover_dir, job.uuid }) catch |err| {
            std.debug.print("Failed to format hover path: {}\n", .{err});
            return;
        };
        defer job.allocator.free(hover_path);

        std.debug.print("Generating silent hover preview: {s}\n", .{hover_path});
        const hover_res = std.process.run(job.allocator, io, .{
            .argv = &[_][]const u8{
                "ffmpeg", "-y", "-i", orig_path,
                "-t", "3",
                "-an", "-c:v", "libsvtav1", "-pix_fmt", "yuv420p10le", "-preset", "12", "-crf", "35",
                "-vf", "scale='min(640,iw)':-2",
                "-movflags", "+faststart", hover_path
            },
        }) catch |err| {
            std.debug.print("Failed to run ffmpeg for hover preview: {}\n", .{err});
            return;
        };
        defer {
            job.allocator.free(hover_res.stdout);
            job.allocator.free(hover_res.stderr);
        }

        // 4. Extract single static frame at 00:00:02
        const temp_frame_path = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}/{s}_frame.jpg", .{ global_config.?.originals_dir, job.username, job.year, job.month, job.uuid }) catch |err| {
            std.debug.print("Failed to format temp frame path: {}\n", .{err});
            return;
        };
        defer job.allocator.free(temp_frame_path);

        const temp_frame_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{temp_frame_path}, 0) catch |err| {
            std.debug.print("Failed to format temp frame path sentinel: {}\n", .{err});
            return;
        };
        defer {
            _ = unlink(temp_frame_path_c.ptr);
            job.allocator.free(temp_frame_path_c);
        }

        const frame_res = std.process.run(job.allocator, io, .{
            .argv = &[_][]const u8{
                "ffmpeg", "-y", "-i", orig_path,
                "-vframes", "1", "-q:v", "2", temp_frame_path
            },
        }) catch |err| {
            std.debug.print("Failed to run ffmpeg frame extraction: {}\n", .{err});
            return;
        };
        defer {
            job.allocator.free(frame_res.stdout);
            job.allocator.free(frame_res.stderr);
        }

        // 5. Build static thumbnails using libvips from the extracted frame
        const target_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ global_config.?.thumbnails_dir, job.username, job.year, job.month }) catch |err| {
            std.debug.print("Failed to format thumbnails directory: {}\n", .{err});
            return;
        };
        defer job.allocator.free(target_dir);

        makeDirPathSync(job.allocator, target_dir) catch |err| {
            std.debug.print("Failed to recursively create thumbnails path '{s}': {}\n", .{ target_dir, err });
            return;
        };

        const output_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.jpg", .{ target_dir, job.uuid }) catch |err| {
            std.debug.print("Failed to format output path: {}\n", .{err});
            return;
        };
        defer job.allocator.free(output_path);

        const out_c = std.fmt.allocPrintSentinel(job.allocator, "{s}[Q={d}]", .{ output_path, job.quality }, 0) catch |err| {
            std.debug.print("Failed to format output path options: {}\n", .{err});
            return;
        };
        defer job.allocator.free(out_c);

        var next_img: ?*vips.VipsImage = null;

        const thumb_res = vips.vips_thumbnail(
            temp_frame_path_c.ptr,
            &next_img,
            @as(c_int, 600),
            "height",
            @as(c_int, 600),
            @as(?*anyopaque, null),
        );
        if (thumb_res != 0) {
            std.debug.print("Failed to generate thumbnail for video: {s}\n", .{vips.vips_error_buffer()});
            return;
        }
        defer if (next_img) |img| vips.g_object_unref(img);

        const write_res = vips.vips_image_write_to_file(next_img, out_c.ptr, @as(?*anyopaque, null));
        if (write_res != 0) {
            std.debug.print("Failed to save video thumbnail: {s}\n", .{vips.vips_error_buffer()});
            return;
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

        db.insertPhoto(record) catch |err| {
            std.debug.print("Failed to insert video metadata: {}\n", .{err});
            return;
        };

        // Complete!
        is_error = false;
        return;
    }

    // Read the original file into memory temporarily to extract EXIF in a closed scope
    const file_buf = blk: {
        const cwd = std.Io.Dir.cwd();
        var orig_file = cwd.openFile(io, orig_path, .{}) catch |err| {
            std.debug.print("Failed to open original file for metadata: {}\n", .{err});
            return;
        };
        defer orig_file.close(io);

        const file_size = (orig_file.stat(io) catch |err| {
            std.debug.print("Failed to stat original file: {}\n", .{err});
            return;
        }).size;

        const file_buf = job.allocator.alloc(u8, @intCast(file_size)) catch |err| {
            std.debug.print("Failed to allocate file buffer: {}\n", .{err});
            return;
        };
        errdefer job.allocator.free(file_buf);

        var file_reader = orig_file.reader(io, &.{});
        file_reader.interface.readSliceAll(file_buf) catch |err| {
            std.debug.print("Failed to read original file contents: {}\n", .{err});
            return;
        };
        break :blk file_buf;
    };
    defer job.allocator.free(file_buf);

    // Extract EXIF data from RAM buffer
    const metadata = exif.extractExifFromBuffer(job.allocator, file_buf) catch |err| {
        std.debug.print("Failed to extract EXIF: {}\n", .{err});
        return;
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
                const new_orig_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ global_config.?.originals_dir, job.username, shooting_year, shooting_month }) catch |err| {
                    std.debug.print("Failed to format new original dir: {}\n", .{err});
                    return;
                };
                defer job.allocator.free(new_orig_dir);

                // Create the target folder recursively
                makeDirPathSync(job.allocator, new_orig_dir) catch |err| {
                    std.debug.print("Failed to create folder '{s}': {}\n", .{ new_orig_dir, err });
                    return;
                };

                // New original path
                const new_orig_path = std.fmt.allocPrint(job.allocator, "{s}/{s}.{s}", .{ new_orig_dir, job.uuid, job.extension }) catch |err| {
                    std.debug.print("Failed to format new original path: {}\n", .{err});
                    return;
                };
                defer job.allocator.free(new_orig_path);

                // Move file using standard C rename
                const old_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{orig_path}, 0) catch |err| {
                    std.debug.print("Failed to format sentinel old path: {}\n", .{err});
                    return;
                };
                defer job.allocator.free(old_path_c);

                const new_path_c = std.fmt.allocPrintSentinel(job.allocator, "{s}", .{new_orig_path}, 0) catch |err| {
                    std.debug.print("Failed to format sentinel new path: {}\n", .{err});
                    return;
                };
                defer job.allocator.free(new_path_c);

                if (rename(old_path_c.ptr, new_path_c.ptr) != 0) {
                    std.debug.print("Failed to rename original photo to shooting date path using C rename\n", .{});
                    return;
                }

                std.debug.print("Moved original from upload date path '{s}' to shooting date path '{s}'\n", .{ orig_path, new_orig_path });

                // Update job properties in memory so subsequent preview/thumbnail generation uses shooting date
                job.allocator.free(job.year);
                job.allocator.free(job.month);
                job.allocator.free(job.day);

                job.year = job.allocator.dupe(u8, shooting_year) catch |err| {
                    std.debug.print("Failed to duplicate shooting year: {}\n", .{err});
                    return;
                };
                job.month = job.allocator.dupe(u8, shooting_month) catch |err| {
                    std.debug.print("Failed to duplicate shooting month: {}\n", .{err});
                    return;
                };
                job.day = job.allocator.dupe(u8, shooting_day) catch |err| {
                    std.debug.print("Failed to duplicate shooting day: {}\n", .{err});
                    return;
                };

                // Update orig_path in memory to point to the new shooting date original folder path
                job.allocator.free(orig_path);
                orig_path = job.allocator.dupe(u8, new_orig_path) catch |err| {
                    std.debug.print("Failed to duplicate new original path: {}\n", .{err});
                    return;
                };
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

    // Extract Full EXIF data for SQLite
    const full_exif_record = exif.extractFullExifFromBuffer(job.allocator, file_buf, job.uuid) catch |err| {
        std.debug.print("Failed to extract full EXIF: {}\n", .{err});
        return;
    };
    defer {
        @setEvalBranchQuota(10000);
        inline for (std.meta.fields(db.PhotoExifRecord)) |field| {
            if (comptime !std.mem.eql(u8, field.name, "uuid")) {
                if (@field(full_exif_record, field.name)) |v| job.allocator.free(v);
            }
        }
        job.allocator.free(full_exif_record.uuid);
    }

    // Write photo metadata and EXIF records into SQLite
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

    db.insertPhoto(record) catch |err| {
        std.debug.print("Failed to insert photo metadata: {}\n", .{err});
        return;
    };
    db.insertPhotoExif(job.username, full_exif_record) catch |err| {
        std.debug.print("Failed to save EXIF data: {}\n", .{err});
    };
    const t_db = vips.getWallMillis();
    logger.logEvent(job.uuid, "database updated (bg)", job.t_start, t_db);

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
        const base_dir = if (std.mem.eql(u8, target.name, "previews")) global_config.?.previews_dir else global_config.?.thumbnails_dir;
        const target_dir = std.fmt.allocPrint(job.allocator, "{s}/{s}/{s}/{s}", .{ base_dir, job.username, job.year, job.month }) catch |err| {
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

    is_error = false;

    const elapsed_ms = vips.getThreadCpuMillis() - t_start;
    std.debug.print("Finished background processing '{s}.{s}' in {d:.2} CPU ms\n", .{ job.uuid, job.extension, elapsed_ms });
}
