const std = @import("std");

pub const OutputConfig = struct {
    name: []const u8,
    target_width: i32,
    target_height: i32,
    directory: []const u8,
};

pub const Config = struct {
    backend: []const u8,
    quality: i32,
    gallery_thumbnail_height: i32,
    input_directory: []const u8,
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
            .directory = try allocator.dupe(u8, out.directory),
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
        .outputs = outputs,
    };
}
