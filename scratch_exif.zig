const std = @import("std");

pub const ExifTag = c_int;
pub extern "c" fn exif_tag_get_name(tag: ExifTag) [*c]const u8;

pub fn main() !void {
    std.debug.print("Supported EXIF Tags:\n", .{});
    
    // Iterate over all possible 16-bit EXIF tag values
    var tag: u32 = 0;
    while (tag <= 0xffff) : (tag += 1) {
        const name_c = exif_tag_get_name(@intCast(tag));
        if (name_c != null) {
            const name = std.mem.span(name_c);
            if (name.len > 0) {
                std.debug.print("0x{x:04}: {s}\n", .{tag, name});
            }
        }
    }
}
