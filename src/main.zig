const std = @import("std");

const Zep = @import("zep.zig");
const Controller = @import("controller/controller.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    // start
    var context = try Zep.start(arena.allocator());
    defer context.deinit();

    try Controller._controller(&context);
}
