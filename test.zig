const std = @import("std");

pub const Record = struct {
    a: u32,
    b: bool,
};

pub fn main() void {
    inline for (comptime std.meta.fieldNames(Record)) |name| {
        std.debug.print("field: {s}\n", .{name});
    }
}
