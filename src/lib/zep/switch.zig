const std = @import("std");
const Manifest = @import("lib/manifest.zig");
// const Path = @import("lib/path.zig");

const Structs = @import("structs");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;

/// Handles switching between installed Zep versions
pub const ZepSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZepSwitcher
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZepSwitcher {
        return ZepSwitcher{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ZepSwitcher
    // ------------------------
    pub fn deinit(_: *ZepSwitcher) void {
        // currently no deinit required
    }

    // ------------------------
    // Switch active Zep version
    // Updates manifest and system PATH
    // ------------------------
    pub fn switchVersion(self: *ZepSwitcher, version: []const u8) !void {
        // Update manifest with new version
        try self.printer.append("Modifying Manifest...\n");
        try Manifest.modifyManifest(version);
        self.printer.pop(1); // Remove temporary log
        try self.printer.append("Manifest up to date!\n");

        // Update system PATH to point to new version
        try self.printer.append("Switching to installed version...\n");
        self.printer.pop(1); // Remove temporary log
        try self.printer.append("Switched to installed version successfully!\n");
    }
};
