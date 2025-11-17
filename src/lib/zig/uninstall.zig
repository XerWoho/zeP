const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

/// Handles uninstalling Zig versions
pub const ZigUninstaller = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZigUninstaller
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZigUninstaller {
        return ZigUninstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize ZigUninstaller
    // ------------------------
    pub fn deinit(_: *ZigUninstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Uninstall a Zig version by deleting its folder
    // ------------------------
    pub fn uninstall(self: *ZigUninstaller, path: []const u8) !void {
        try self.printer.append("Deleting Zig version at path: ");
        try self.printer.append(path);
        try self.printer.append("\n");

        // Recursively delete folder
        try UtilsFs.delTree(path);

        try self.printer.append("Zig version deleted successfully.\n\n");
    }
};
