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
    const manifest = UtilsManifest.readManifest(Structs.ZigManifest, allocator, Constants.ROOT_ZEP_ZIG_MANIFEST) catch {
        @panic("Reading Manifest failed!");
    };

    defer manifest.deinit();
    const absPath = try std.fs.realpathAlloc(allocator, manifest.value.path);
    defer allocator.free(absPath);

    if (builtin.os.tag == .windows) {
        const zigExe = try std.fmt.allocPrint(allocator, "{s}/zig.exe", .{absPath});
        defer allocator.free(zigExe);
        if (!UtilsFs.checkFileExists(zigExe)) {
            @panic("Zig exe does not exists!");
        }

        const linkExePathDir = try std.fmt.allocPrint(allocator, "{s}/e/", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        if (!UtilsFs.checkDirExists(linkExePathDir)) {
            std.fs.cwd().makePath(linkExePathDir) catch {
                @panic("Making path!");
            };
        }

        const linkExePath = try std.fmt.allocPrint(allocator, "{s}/e/zig.exe", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        defer allocator.free(linkExePath);
        if (UtilsFs.checkFileExists(linkExePath)) {
            std.fs.cwd().deleteFile(linkExePath) catch {
                @panic("Deleting!");
            };
        }

        std.fs.cwd().symLink(zigExe, linkExePath, .{ .is_directory = false }) catch {
            @panic("Symlink failed windows!");
        };
    } else {
        const zigExe = try std.fmt.allocPrint(allocator, "{s}/zig", .{absPath});
        defer allocator.free(zigExe);
        if (!UtilsFs.checkFileExists(zigExe)) {
            @panic("Zig exe does not exists!");
        }

        const zigExeTarget = try std.fs.cwd().openFile(zigExe, .{});
        defer zigExeTarget.close();
        zigExeTarget.chmod(755) catch {
            @panic("chmod 755!");
        };

        try UtilsFs.delFile("/usr/local/bin/zig");
        std.fs.cwd().symLink(zigExe, "/usr/local/bin/zig", .{ .is_directory = false }) catch {
            @panic("Symlink failed linux!");
        };
    }
}
