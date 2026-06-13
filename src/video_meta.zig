const std = @import("std");
const db = @import("db.zig");

pub fn extractVideoMetadata(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, uuid: []const u8) !db.VideoMetadataRecord {
    var record = db.VideoMetadataRecord{
        .uuid = try allocator.dupe(u8, uuid),
    };

    const res = std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            file_path,
        },
    }) catch |err| {
        std.debug.print("Failed to run ffprobe: {}\n", .{err});
        return record;
    };
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, res.stdout, .{}) catch |err| {
        std.debug.print("Failed to parse ffprobe json: {}\n", .{err});
        return record;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return record;

    if (root.object.get("streams")) |streams| {
        if (streams == .array and streams.array.items.len > 0) {
            for (streams.array.items) |stream| {
                if (stream != .object) continue;
                if (stream.object.get("codec_type")) |ctype| {
                    if (ctype == .string and std.mem.eql(u8, ctype.string, "video")) {
                        if (stream.object.get("codec_name")) |v| {
                            if (v == .string) record.codec_name = try allocator.dupe(u8, v.string);
                        }
                        if (stream.object.get("width")) |v| {
                            if (v == .integer) record.width = try std.fmt.allocPrint(allocator, "{d}", .{v.integer});
                        }
                        if (stream.object.get("height")) |v| {
                            if (v == .integer) record.height = try std.fmt.allocPrint(allocator, "{d}", .{v.integer});
                        }
                        if (stream.object.get("r_frame_rate")) |v| {
                            if (v == .string) record.frame_rate = try allocator.dupe(u8, v.string);
                        }
                        if (stream.object.get("tags")) |tags| {
                            if (tags == .object) {
                                if (tags.object.get("encoder")) |v| {
                                    if (v == .string) record.encoder = try allocator.dupe(u8, v.string);
                                }
                                if (tags.object.get("creation_time")) |v| {
                                    if (v == .string) record.creation_time = try allocator.dupe(u8, v.string);
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    if (root.object.get("format")) |format| {
        if (format == .object) {
            if (format.object.get("format_name")) |v| {
                if (v == .string) record.format_name = try allocator.dupe(u8, v.string);
            }
            if (format.object.get("duration")) |v| {
                if (v == .string) record.duration = try allocator.dupe(u8, v.string);
            }
            if (format.object.get("bit_rate")) |v| {
                if (v == .string) record.bit_rate = try allocator.dupe(u8, v.string);
            }
            if (format.object.get("tags")) |tags| {
                if (tags == .object) {
                    if (record.encoder == null) {
                        if (tags.object.get("encoder")) |v| {
                            if (v == .string) record.encoder = try allocator.dupe(u8, v.string);
                        }
                    }
                    if (record.creation_time == null) {
                        if (tags.object.get("creation_time")) |v| {
                            if (v == .string) record.creation_time = try allocator.dupe(u8, v.string);
                        }
                    }
                    if (tags.object.get("location")) |v| {
                        if (v == .string) record.location = try allocator.dupe(u8, v.string);
                    }
                }
            }
        }
    }

    return record;
}
