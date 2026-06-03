const std = @import("std");

pub const OutputConfig = struct {
    name: []const u8,
    target_width: i32,
    target_height: i32,
};

pub const Config = struct {
    backend: []const u8,
    quality: i32,
    gallery_thumbnail_height: i32,
    input_directory: []const u8,
    db_dir: []const u8,
    originals_dir: []const u8,
    previews_dir: []const u8,
    thumbnails_dir: []const u8,
    hover_previews_dir: []const u8,
    outputs: []OutputConfig,
};

pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Config {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;

    var out_buf: [1024 * 10]u8 = undefined; // 10KB is plenty
    const size = try reader.readSliceShort(&out_buf);

    const parsed = try std.json.parseFromSlice(Config, allocator, out_buf[0..size], .{});
    defer parsed.deinit();

    // Deep copy slices to ensure they persist after parsed deinitialization
    const outputs = try allocator.alloc(OutputConfig, parsed.value.outputs.len);
    for (parsed.value.outputs, 0..) |out, i| {
        outputs[i] = .{
            .name = try allocator.dupe(u8, out.name),
            .target_width = out.target_width,
            .target_height = out.target_height,
        };
    }

    // Sort outputs from largest to smallest by target_height for the cascade optimization
    std.mem.sort(OutputConfig, outputs, {}, struct {
        fn lessThan(_: void, a: OutputConfig, b: OutputConfig) bool {
            return a.target_height > b.target_height;
        }
    }.lessThan);

    return .{
        .backend = try allocator.dupe(u8, parsed.value.backend),
        .quality = parsed.value.quality,
        .gallery_thumbnail_height = parsed.value.gallery_thumbnail_height,
        .input_directory = try allocator.dupe(u8, parsed.value.input_directory),
        .db_dir = try allocator.dupe(u8, parsed.value.db_dir),
        .originals_dir = try allocator.dupe(u8, parsed.value.originals_dir),
        .previews_dir = try allocator.dupe(u8, parsed.value.previews_dir),
        .thumbnails_dir = try allocator.dupe(u8, parsed.value.thumbnails_dir),
        .hover_previews_dir = try allocator.dupe(u8, parsed.value.hover_previews_dir),
        .outputs = outputs,
    };
}

pub fn saveConfig(io: std.Io, path: []const u8, config: Config) !void {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    var write_buffer: [1024 * 10]u8 = undefined;
    var buffered_writer = file.writer(io, &write_buffer);
    const writer = &buffered_writer.interface;

    try std.json.Stringify.value(config, .{ .whitespace = .indent_4 }, writer);
    try buffered_writer.flush();
}

pub fn parseConfigJson(allocator: std.mem.Allocator, json: []const u8) !Config {
    const parsed = try std.json.parseFromSlice(Config, allocator, json, .{});
    defer parsed.deinit();

    // Deep copy slices to ensure they persist after parsed deinitialization
    const outputs = try allocator.alloc(OutputConfig, parsed.value.outputs.len);
    for (parsed.value.outputs, 0..) |out, i| {
        outputs[i] = .{
            .name = try allocator.dupe(u8, out.name),
            .target_width = out.target_width,
            .target_height = out.target_height,
        };
    }

    // Sort outputs from largest to smallest by target_height for the cascade optimization
    std.mem.sort(OutputConfig, outputs, {}, struct {
        fn lessThan(_: void, a: OutputConfig, b: OutputConfig) bool {
            return a.target_height > b.target_height;
        }
    }.lessThan);

    return .{
        .backend = try allocator.dupe(u8, parsed.value.backend),
        .quality = parsed.value.quality,
        .gallery_thumbnail_height = parsed.value.gallery_thumbnail_height,
        .input_directory = try allocator.dupe(u8, parsed.value.input_directory),
        .db_dir = try allocator.dupe(u8, parsed.value.db_dir),
        .originals_dir = try allocator.dupe(u8, parsed.value.originals_dir),
        .previews_dir = try allocator.dupe(u8, parsed.value.previews_dir),
        .thumbnails_dir = try allocator.dupe(u8, parsed.value.thumbnails_dir),
        .hover_previews_dir = try allocator.dupe(u8, parsed.value.hover_previews_dir),
        .outputs = outputs,
    };
}
