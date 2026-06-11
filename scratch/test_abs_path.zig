const std = @import("std");

pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
        .async_limit = .unlimited,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    // Try to open /etc/passwd or /etc/hosts as a test
    var file = cwd.openFile(io, "/etc/hosts", .{}) catch |err| {
        std.debug.print("Failed to open absolute path: {}\n", .{err});
        return;
    };
    defer file.close(io);

    std.debug.print("Successfully opened absolute path /etc/hosts\n", .{});
}
