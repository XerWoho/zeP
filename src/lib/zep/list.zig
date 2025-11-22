const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;
const UtilsJson = Utils.UtilsJson;

/// Lists installed Zep versions
pub const ZepLister = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZepLister
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZepLister {
        return ZepLister{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ZepLister
    // ------------------------
    pub fn deinit(_: *ZepLister) void {
        // currently no deinit required
    }

    // ------------------------
    // Print all installed Zep versions
    // Marks the version currently in use
    // ------------------------
    pub fn listVersions(self: *ZepLister) !void {
        try self.printer.append("\nAvailable Zep Versions:\n", .{}, .{});

        const versionsDir = try std.fmt.allocPrint(self.allocator, "{s}/v/", .{Constants.ROOT_ZEP_ZEP_FOLDER});
        defer self.allocator.free(versionsDir);

        if (!UtilsFs.checkDirExists(versionsDir)) {
            try self.printer.append("No versions installed!\n\n", .{}, .{});
            return;
        }

        if (!UtilsFs.checkFileExists(Constants.ROOT_ZEP_ZEP_MANIFEST)) {
            var json = try UtilsJson.Json.init(self.allocator);
            try json.writePretty(Constants.ROOT_ZEP_ZEP_MANIFEST, Structs.ZepManifest{
                .version = "",
                .path = "",
            });
        }

        const manifestTarget = Constants.ROOT_ZEP_ZEP_MANIFEST;
        const openManifest = try UtilsFs.openFile(manifestTarget);
        defer openManifest.close();

        const readOpenManifest = try openManifest.readToEndAlloc(self.allocator, 1024 * 1024);
        const parsedManifest = try std.json.parseFromSlice(Structs.ZepManifest, self.allocator, readOpenManifest, .{});
        defer parsedManifest.deinit();

        const dir = try std.fs.cwd().openDir(versionsDir, std.fs.Dir.OpenDirOptions{ .iterate = true });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;

            const versionName = try self.allocator.dupe(u8, entry.name);
            // Mark version as in-use if it matches the manifest
            if (std.mem.containsAtLeast(u8, parsedManifest.value.path, 1, versionName)) {
                try self.printer.append("{s} (in-use)\n", .{versionName}, .{});
            } else {
                try self.printer.append("{s}\n", .{versionName}, .{});
            }
        }

        try self.printer.append("\n", .{}, .{});
    }
};
