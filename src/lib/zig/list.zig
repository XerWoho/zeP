const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;
const UtilsManifest = Utils.UtilsManifest;

/// Lists installed Zig versions
pub const ZigLister = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZigLister
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZigLister {
        return ZigLister{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ZigLister
    // ------------------------
    pub fn deinit(_: *ZigLister) void {
        // currently no deinit required
    }

    // ------------------------
    // Print all installed Zig versions
    // Marks the version currently in use
    // ------------------------
    pub fn listVersions(self: *ZigLister) !void {
        try self.printer.append("\nAvailable Zig Versions:\n", .{}, .{});

        const versionsDir = try std.fmt.allocPrint(self.allocator, "{s}/d/", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        defer self.allocator.free(versionsDir);

        if (!UtilsFs.checkDirExists(versionsDir)) {
            try self.printer.append("No versions installed!\n\n", .{}, .{});
            return;
        }

        const manifest = try UtilsManifest.readManifest(Structs.ZigManifest, self.allocator, Constants.ROOT_ZEP_ZIG_MANIFEST);
        defer manifest.deinit();
        if (manifest.value.path.len == 0) {
            std.debug.print("\nManifest path is not defined! Use\n $ zep zig switch <zig-version>\nTo fix!\n", .{});
            std.process.exit(0);
            return;
        }
        const dir = try std.fs.cwd().openDir(versionsDir, std.fs.Dir.OpenDirOptions{ .iterate = true });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;

            const versionName = try self.allocator.dupe(u8, entry.name);
            // Mark version as in-use if it matches the manifest
            if (std.mem.containsAtLeast(u8, manifest.value.path, 1, versionName)) {
                try self.printer.append("{s} (in-use)\n", .{versionName}, .{});
            } else {
                try self.printer.append("{s}\n", .{versionName}, .{});
            }
        }

        try self.printer.append("\n", .{}, .{});
    }
};
