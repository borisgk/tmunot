const std = @import("std");

pub fn main() !void {
    const std_path = @import("builtin").recipe orelse "unknown";
    std.debug.print("std path: {s}\n", .{std_path});
}
