const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");

const Structs = @import("structs");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsManifest = Utils.UtilsManifest;
const UtilsJson = Utils.UtilsJson;

/// Updates the symbolic link to point to the currently active Zig installation
pub fn updateLink() !void {
    var allocator = std.heap.page_allocator;

    // Load manifest and get absolute path
    const manifest = try UtilsManifest.readManifest(Structs.ZigManifest, allocator, Constants.ROOT_ZEP_ZIG_MANIFEST);
    defer manifest.deinit();
    const absPath = try std.fs.realpathAlloc(allocator, manifest.value.path);
    defer allocator.free(absPath);

    const zigExe = try std.fmt.allocPrint(allocator, "{s}/zig.exe", .{absPath});
    defer allocator.free(zigExe);

    if (builtin.os.tag == .windows) {
        const linkExePathDir = try std.fmt.allocPrint(allocator, "{s}/e/", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        if (!try UtilsFs.checkDirExists(linkExePathDir)) {
            try std.fs.cwd().makePath(linkExePathDir);
        }

        const linkExePath = try std.fmt.allocPrint(allocator, "{s}/e/zig.exe", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        defer allocator.free(linkExePath);
        if (try UtilsFs.checkFileExists(linkExePath)) {
            try std.fs.cwd().deleteFile(linkExePath);
        }

        try std.fs.cwd().symLink(zigExe, linkExePath, .{ .is_directory = false });
    } else {
        const zigExeTarget = try std.fs.cwd().openFile(zigExe, .{});
        defer zigExeTarget.close();
        try zigExeTarget.chmod(755);

        try std.fs.cwd().symLink(zigExe, "/usr/local/bin/zig", .{ .is_directory = false });
    }
}
