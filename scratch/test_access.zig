const std = @import("std");
pub fn main() !void {
    std.posix.access("scratch", std.posix.F_OK) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    std.debug.print("Exists!\n", .{});
}
