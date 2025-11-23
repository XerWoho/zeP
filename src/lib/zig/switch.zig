const std = @import("std");
const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;
const UtilsManifest = Utils.UtilsManifest;
const UtilsJson = Utils.UtilsJson;

/// Handles switching between installed Zig versions
pub const ZigSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZigSwitcher
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZigSwitcher {
        return ZigSwitcher{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ZigSwitcher
    // ------------------------
    pub fn deinit(_: *ZigSwitcher) void {
        // currently no deinit required
    }

    // ------------------------
    // Switch active Zig version
    // Updates manifest and system PATH
    // ------------------------
    pub fn switchVersion(self: *ZigSwitcher, name: []const u8, version: []const u8, target: []const u8) !void {
        // Update manifest with new version
        try self.printer.append("Modifying Manifest...\n", .{}, .{});
        const path = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}/{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, version, target });
        UtilsManifest.writeManifest(
            Structs.ZigManifest,
            self.allocator,
            Constants.ROOT_ZEP_ZIG_MANIFEST,
            Structs.ZigManifest{ .name = name, .path = path },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        // Update zep.json and zep.lock
        blk: {
            // all need to match for it to be in a zeP project
            if (!UtilsFs.checkFileExists(Constants.ZEP_LOCK_PACKAGE_FILE) or
                !UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE) or
                !UtilsFs.checkDirExists(Constants.ZEP_FOLDER)) break :blk;

            var pkg = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);
            defer pkg.deinit();
            var lock = try UtilsManifest.readManifest(Structs.PackageLockStruct, self.allocator, Constants.ZEP_LOCK_PACKAGE_FILE);
            defer lock.deinit();

            pkg.value.zigVersion = version;
            lock.value.root = pkg.value;
            UtilsManifest.writeManifest(
                Structs.PackageJsonStruct,
                self.allocator,
                Constants.ZEP_PACKAGE_FILE,
                pkg.value,
            ) catch {
                try self.printer.append("Updating Json Manifest failed!\n", .{}, .{ .color = 31 });
            };
            UtilsManifest.writeManifest(
                Structs.PackageLockStruct,
                self.allocator,
                Constants.ZEP_LOCK_PACKAGE_FILE,
                lock.value,
            ) catch {
                try self.printer.append("Updating Lock Manifest failed!\n", .{}, .{ .color = 31 });
            };
            break :blk;
        }

        try self.printer.append("Manifests up to date!\n", .{}, .{});

        // Update system PATH to point to new version
        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink() catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Switched to installed version successfully!\n", .{}, .{ .color = 32 });
    }
};
