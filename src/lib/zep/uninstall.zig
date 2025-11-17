const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

/// Handles uninstalling Zep versions
pub const ZepUninstaller = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZepUninstaller
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZepUninstaller {
        return ZepUninstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize ZepUninstaller
    // ------------------------
    pub fn deinit(_: *ZepUninstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Uninstall a Zep version by deleting its folder
    // ------------------------
    pub fn uninstall(self: *ZepUninstaller, version: []const u8) !void {
        try self.printer.append("Deleting Zep version ");
        try self.printer.append(version);
        try self.printer.append(" now...\n");

        // Recursively delete folder
        const path = try std.fmt.allocPrint(self.allocator, "{s}/v/{s}", .{ Constants.ROOT_ZEP_ZEP_FOLDER, version });
        defer self.allocator.free(path);
        try UtilsFs.delTree(path);

        try self.printer.append("Zep version deleted successfully.\n\n");
    }
};
