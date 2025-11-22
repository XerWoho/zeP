const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const UtilsFs = @import("fs.zig");
const UtilsPrinter = @import("printer.zig");

fn mkdir(path: []const u8, printer: *UtilsPrinter.Printer) !void {
    if (UtilsFs.checkDirExists(path)) return;
    std.fs.cwd().makePath(path) catch |err| {
        switch (err) {
            error.AccessDenied => {
                try printer.append("Creating {s} Failed! (Admin Privelege required)\n", .{path}, .{});
                return;
            },
            else => return,
        }
    };
}

pub fn setup(printer: *UtilsPrinter.Printer) !void {
    const paths = [5][]const u8{ Constants.ROOT_ZEP_FOLDER, Constants.ROOT_ZEP_ZEPPED_FOLDER, Constants.ROOT_ZEP_PKG_FOLDER, Constants.ROOT_ZEP_ZEPPED_FOLDER, Constants.ROOT_ZEP_ZIG_FOLDER };
    for (paths) |p| {
        try mkdir(p, printer);
    }
}
