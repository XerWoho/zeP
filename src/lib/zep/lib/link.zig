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
    const allocator = std.heap.page_allocator;

    // Load manifest and get absolute path
    const manifest = try UtilsManifest.readManifest(Structs.ZepManifest, allocator, Constants.ROOT_ZEP_ZEP_MANIFEST);
    defer manifest.deinit();

    const absPath = try std.fs.realpathAlloc(allocator, manifest.value.path);
    defer allocator.free(absPath);

    const manifestTarget = Constants.ROOT_ZEP_ZEP_MANIFEST;
    const openManifest = try UtilsFs.openFile(manifestTarget);
    defer openManifest.close();

    const readOpenManifest = try openManifest.readToEndAlloc(allocator, 1024 * 1024);
    const parsedManifest = try std.json.parseFromSlice(Structs.ZepManifest, allocator, readOpenManifest, .{});
    defer parsedManifest.deinit();

    if (builtin.os.tag == .windows) {
        const zepExePath = try std.fmt.allocPrint(allocator, "{s}/zep.exe", .{parsedManifest.value.path});
        defer allocator.free(zepExePath);

        const linkExePathDir = try std.fmt.allocPrint(allocator, "{s}/e/", .{Constants.ROOT_ZEP_ZEP_FOLDER});
        if (!UtilsFs.checkDirExists(linkExePathDir)) {
            try std.fs.cwd().makePath(linkExePathDir);
        }

        const linkExePath = try std.fmt.allocPrint(allocator, "{s}/e/zep.exe", .{Constants.ROOT_ZEP_ZEP_FOLDER});
        defer allocator.free(linkExePath);
        if (UtilsFs.checkFileExists(linkExePath)) {
            try std.fs.cwd().deleteFile(linkExePath);
        }
        try std.fs.cwd().symLink(zepExePath, linkExePath, .{ .is_directory = false });
    } else {
        const zepExePath = try std.fmt.allocPrint(allocator, "{s}/zeP", .{parsedManifest.value.path});
        defer allocator.free(zepExePath);

        const zepExeTarget = try std.fs.cwd().openFile(zepExePath, .{});
        defer zepExeTarget.close();
        try zepExeTarget.chmod(755);

        try std.fs.cwd().symLink(zepExePath, "/usr/local/bin/zeP", .{ .is_directory = false });
    }
}
