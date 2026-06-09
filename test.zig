const std = @import("std");
pub fn main() void {
    var prng = std.Random.DefaultPrng.init(0);
    _ = prng;
    std.debug.print("ok\n", .{});
}
