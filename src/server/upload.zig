const std = @import("std");

const config_mod = @import("../config.zig");
const processor = @import("../processor.zig");
const exif = @import("../exif.zig");
const vips = @import("../vips.zig");
const db = @import("../db.zig");
const logger = @import("../logger.zig");

fn generateUuid(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    var bytes: [16]u8 = undefined;
    try io.randomSecure(&bytes);

    // Version 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Variant 1
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return try std.fmt.allocPrint(allocator,
        "{0x:02}{1x:02}{2x:02}{3x:02}-{4x:02}{5x:02}-{6x:02}{7x:02}-{8x:02}{9x:02}-{10x:02}{11x:02}{12x:02}{13x:02}{14x:02}{15x:02}",
        .{
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        }
    );
}

extern "c" fn time(t: ?*i64) i64;

fn getCurrentDateTime(allocator: std.mem.Allocator) !struct { year: []const u8, month: []const u8, day: []const u8, iso_str: []const u8 } {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(time(null)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    const numeric_month = month_day.month.numeric();
    const numeric_day = month_day.day_index + 1;

    const year_str = try std.fmt.allocPrint(allocator, "{0d:0>4}", .{year_day.year});
    const month_str = try std.fmt.allocPrint(allocator, "{0d:0>2}", .{numeric_month});
    const day_str = try std.fmt.allocPrint(allocator, "{0d:0>2}", .{numeric_day});
    const iso_str = try std.fmt.allocPrint(allocator, "{0d:0>4}-{1d:0>2}-{2d:0>2} {3d:0>2}:{4d:0>2}:{5d:0>2}", .{
        year_day.year,
        numeric_month,
        numeric_day,
        hour,
        minute,
        second,
    });

    return .{
        .year = year_str,
        .month = month_str,
        .day = day_str,
        .iso_str = iso_str,
    };
}

pub fn handleUpload(
    req: *std.http.Server.Request,
    io: std.Io,
    req_alloc: std.mem.Allocator,
    config: config_mod.Config,
    is_authenticated: bool,
    username: ?[]const u8,
    multipart_boundary: []const u8,
) !void {
    if (!is_authenticated or username == null) {
        try req.respond("Unauthorized", .{ .status = .unauthorized });
        return;
    }

    if (multipart_boundary.len == 0) {
        try req.respond("Missing multipart boundary", .{ .status = .bad_request });
        return;
    }

    const user = try req_alloc.dupe(u8, username.?);

    // Read the multipart body (allowing up to 50MB)
    var buf: [1024]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body = r.allocRemaining(req_alloc, .limited(50 * 1024 * 1024)) catch |err| {
        std.debug.print("Error reading body: {}\n", .{err});
        try req.respond("Request body too large or error reading", .{ .status = .payload_too_large });
        return;
    };
    // body and user are in req_alloc arena, freed on function return.
    const t_received = vips.getWallMillis();

    // Parse boundary headers
    const header_end = std.mem.indexOf(u8, body, "\r\n\r\n") orelse {
        try req.respond("Invalid multipart body", .{ .status = .bad_request });
        return;
    };
    const part_headers = body[0..header_end];

    var filename: []const u8 = "";
    if (std.mem.indexOf(u8, part_headers, "filename=\"")) |fn_idx| {
        const start = fn_idx + 10;
        if (std.mem.indexOfScalar(u8, part_headers[start..], '"')) |end_idx| {
            filename = part_headers[start .. start + end_idx];
        }
    }

    if (filename.len == 0) {
        try req.respond("Missing filename in multipart", .{ .status = .bad_request });
        return;
    }

    const clean_filename = std.fs.path.basename(filename);
    if (clean_filename.len == 0 or std.mem.eql(u8, clean_filename, ".") or std.mem.eql(u8, clean_filename, "..")) {
        try req.respond("Invalid filename", .{ .status = .bad_request });
        return;
    }

    // Construct ending boundary delimiter (\r\n--{boundary})
    const delimiter = try std.fmt.allocPrint(req_alloc, "\r\n--{s}", .{multipart_boundary});

    const file_start = header_end + 4;
    const delimiter_idx = std.mem.indexOf(u8, body[file_start..], delimiter) orelse {
        try req.respond("Malformed multipart data: boundary delimiter not found", .{ .status = .bad_request });
        return;
    };
    const file_content = body[file_start .. file_start + delimiter_idx];

    // 2. Determine target file extension
    const ext = std.fs.path.extension(clean_filename);
    var ext_lower = try req_alloc.alloc(u8, ext.len);
    defer req_alloc.free(ext_lower);
    for (ext, 0..) |c, i| {
        ext_lower[i] = std.ascii.toLower(c);
    }
    const ext_clean = if (std.mem.startsWith(u8, ext_lower, ".")) ext_lower[1..] else ext_lower;

        // 3. Resolve calendar metrics (use current time for original photo directory path)
    const current_time = try getCurrentDateTime(req_alloc);
    defer req_alloc.free(current_time.year);
    defer req_alloc.free(current_time.month);
    defer req_alloc.free(current_time.day);
    defer req_alloc.free(current_time.iso_str);

    const year = current_time.year;
    const month = current_time.month;
    const day = current_time.day;

    // 4. Generate UUID
    const uuid = try generateUuid(req_alloc, io);
    defer req_alloc.free(uuid);

    logger.logEvent(uuid, "file received", t_received, t_received);

    // 5. Write original photo to <originals_dir>/<username>/<year>/<month>/<uuid>.<ext>
    const orig_dir = try std.fmt.allocPrint(req_alloc, "{s}/{s}/{s}/{s}", .{ config.originals_dir, user, year, month });
    defer req_alloc.free(orig_dir);

    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, orig_dir) catch |err| {
        std.debug.print("Failed to create directory {s}: {}\n", .{ orig_dir, err });
        try req.respond("Internal Server Error", .{ .status = .internal_server_error });
        return;
    };

    const orig_path = try std.fmt.allocPrint(req_alloc, "{s}/{s}.{s}", .{ orig_dir, uuid, ext_clean });
    defer req_alloc.free(orig_path);

    var file = try cwd.createFile(io, orig_path, .{});
    defer file.close(io);
    var writer = file.writer(io, &.{});
    try writer.interface.writeAll(file_content);

    std.debug.print("Saved original file: {s}\n", .{orig_path});

    // 6. Register job in ActiveJobsRegistry as pending
    try processor.registerJob(uuid, user, year, month, ext_clean);

    // 7. Allocate a FileJob on page_allocator for the background worker queue.
    const job_alloc = std.heap.page_allocator;

    const job = try job_alloc.create(processor.FileJob);
    job.* = .{
        .allocator = job_alloc,
        .uuid = try job_alloc.dupe(u8, uuid),
        .username = try job_alloc.dupe(u8, user),
        .filename = try job_alloc.dupe(u8, clean_filename),
        .year = try job_alloc.dupe(u8, year),
        .month = try job_alloc.dupe(u8, month),
        .day = try job_alloc.dupe(u8, day),
        .upload_date = try job_alloc.dupe(u8, current_time.iso_str),
        .extension = try job_alloc.dupe(u8, ext_clean),
        .quality = config.quality,
        .t_start = t_received,
    };

    // Push the job to the background processing queue
    processor.pushJob(job);

    // Wait for the background thumbnail processing to complete
    // This allows the browser's single XHR POST to act as both the upload AND processing progress,
    // unifying signaling without requiring SSE.
    while (processor.isJobActive(uuid)) {
        try io.sleep(std.Io.Duration.fromMilliseconds(250), .awake);
    }

    const response_body = try std.fmt.allocPrint(req_alloc,
        "{{\"status\":\"success\",\"uuid\":\"{s}\",\"ext\":\"{s}\"}}",
        .{ uuid, ext_clean },
    );
    try req.respond(response_body, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}
