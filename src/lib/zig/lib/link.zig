const std = @import("std");
const builtin = @import("builtin");

const Manifest = @import("manifest.zig");
const Constants = @import("constants");

const Structs = @import("structs");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;

/// Updates the symbolic link to point to the currently active Zig installation
pub fn updateLink() !void {
    const allocator = std.heap.page_allocator;

    // Load manifest and get absolute path
    const manifest = try Manifest.getManifest();
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
        // Windows: use powershell script to modify PATH
        const combinedPath = try std.fmt.allocPrint(allocator, "{s}/zig.exe", .{absPath});
        defer allocator.free(combinedPath);

        const script = try std.fmt.allocPrint(allocator, "{s}/scripts/p/path.ps1", .{parsedManifest.value.path});
        defer allocator.free(script);

        const argv = &[_][]const u8{ "powershell.exe", "-File", script, combinedPath };
        var process = std.process.Child.init(argv, allocator);
        try process.spawn();
        _ = try process.wait();
        _ = try process.kill();
    } else {
        // POSIX: use shell script to modify PATH
        const combinedPath = try std.fmt.allocPrint(allocator, "{s}/zig", .{absPath});
        defer allocator.free(combinedPath);

        const script = try std.fmt.allocPrint(allocator, "{s}/scripts/p/path.sh", .{parsedManifest.value.path});
        defer allocator.free(script);

        const argv = &[_][]const u8{ script, combinedPath };
        var process = std.process.Child.init(argv, allocator);
        try process.spawn();
        _ = try process.wait();
        _ = try process.kill();
    }
}
