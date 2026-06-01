const std = @import("std");
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var list = std.ArrayList([]const u8).empty;
    try list.append(alloc, "user1");
    try list.append(alloc, "user2");
    const users = try list.toOwnedSlice(alloc);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    try std.json.Stringify.value(users, .{}, &aw.writer);
    std.debug.print("JSON: {s}\n", .{aw.written()});
}
