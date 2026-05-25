const std = @import("std");
const auth = @import("../auth.zig");
const config_mod = @import("../config.zig");
const processor = @import("../processor.zig");

pub fn handleUpload(
    req: *std.http.Server.Request,
    io: std.Io,
    auth_ctx: *auth.AuthContext,
    config: config_mod.Config,
    is_authenticated: bool,
    multipart_boundary: []const u8,
) !void {
    if (!is_authenticated) {
        try req.respond("Unauthorized", .{ .status = .unauthorized });
        return;
    }

    if (multipart_boundary.len == 0) {
        try req.respond("Missing multipart boundary", .{ .status = .bad_request });
        return;
    }

    // Read the multipart body (allowing up to 50MB)
    var buf: [1024]u8 = undefined;
    var r = req.readerExpectNone(&buf);
    const body = r.allocRemaining(auth_ctx.allocator, .limited(50 * 1024 * 1024)) catch |err| {
        std.debug.print("Error reading body: {}\n", .{err});
        try req.respond("Request body too large or error reading", .{ .status = .payload_too_large });
        return;
    };
    defer auth_ctx.allocator.free(body);

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

    // Sanitize filename to avoid path traversal vulnerabilities
    const clean_filename = std.fs.path.basename(filename);
    if (clean_filename.len == 0 or std.mem.eql(u8, clean_filename, ".") or std.mem.eql(u8, clean_filename, "..")) {
        try req.respond("Invalid filename", .{ .status = .bad_request });
        return;
    }

    // Construct ending boundary delimiter (\r\n--{boundary})
    const delimiter = try std.fmt.allocPrint(auth_ctx.allocator, "\r\n--{s}", .{multipart_boundary});
    defer auth_ctx.allocator.free(delimiter);

    const file_start = header_end + 4;
    const delimiter_idx = std.mem.indexOf(u8, body[file_start..], delimiter) orelse {
        try req.respond("Malformed multipart data: boundary delimiter not found", .{ .status = .bad_request });
        return;
    };
    const file_content = body[file_start .. file_start + delimiter_idx];

    // Save raw image to ./input/
    const input_path = try std.fs.path.join(auth_ctx.allocator, &.{ config.input_directory, clean_filename });
    defer auth_ctx.allocator.free(input_path);

    const cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, input_path, .{});
    defer file.close(io);
    var writer = file.writer(io, &.{});
    try writer.interface.writeAll(file_content);

    std.debug.print("Saved uploaded file to {s}\n", .{input_path});

    // Trigger cascade processing job (which also extracts EXIF data in the background)
    const job = try auth_ctx.allocator.create(processor.FileJob);
    job.* = .{
        .allocator = auth_ctx.allocator,
        .io = io,
        .input_path = try auth_ctx.allocator.dupe(u8, input_path),
        .filename = try auth_ctx.allocator.dupe(u8, clean_filename),
        .outputs = try auth_ctx.allocator.alloc(config_mod.OutputConfig, config.outputs.len),
        .quality = config.quality,
    };
    for (config.outputs, 0..) |out, idx| {
        job.outputs[idx] = .{
            .name = try auth_ctx.allocator.dupe(u8, out.name),
            .target_width = out.target_width,
            .target_height = out.target_height,
            .directory = try auth_ctx.allocator.dupe(u8, out.directory),
        };
    }

    const thread = try std.Thread.spawn(.{}, processor.worker, .{job});
    thread.detach();

    try req.respond("{\"status\":\"success\",\"message\":\"Image uploaded and processing started in background.\"}", .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}
