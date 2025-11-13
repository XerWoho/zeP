const std = @import("std");
const builtin = @import("builtin");

const Manifest = @import("manifest.zig");
const Constants = @import("constants");

const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;

pub fn modifyPath() !void {
    const allocator = std.heap.page_allocator;

    const manifest = try Manifest.getManifest();
    defer manifest.deinit();
    const absPath = try std.fs.realpathAlloc(allocator, manifest.value.path);

    if (builtin.os.tag == .windows) {
        const combinedPath = try std.fmt.allocPrint(allocator, "{s}/zig.exe", .{absPath});
        const script = try std.fmt.allocPrint(allocator, "{s}/p/path.ps1", .{Constants.ROOT_ZEP_SCRIPTS});
        defer allocator.free(script);
        const argv = &[4][]const u8{ "powershell.exe", "-File", script, combinedPath };
        var process = std.process.Child.init(argv, allocator);
        try process.spawn();
        _ = try process.wait();
        _ = try process.kill();
    } else {
        const combinedPath = try std.fmt.allocPrint(allocator, "{s}/zig", .{absPath});
        const executer = try std.fmt.allocPrint(allocator, "{s}/p/path.sh", .{Constants.ROOT_ZEP_SCRIPTS});
        defer allocator.free(executer);

        const argv = &[2][]const u8{ executer, combinedPath };
        var process = std.process.Child.init(argv, allocator);
        try process.spawn();
        _ = try process.wait();
        _ = try process.kill();
    }
}
