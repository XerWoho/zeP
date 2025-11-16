const std = @import("std");
const Manifest = @import("lib/manifest.zig");
const Path = @import("lib/path.zig");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;

pub const ZigSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !ZigSwitcher {
        return ZigSwitcher{ .allocator = allocator, .printer = printer };
    }

    pub fn deinit(self: *ZigSwitcher) void {
        _ = self;
        defer {
            // self.printer.deinit();
        }
    }

    pub fn switchVersion(self: *ZigSwitcher, name: []const u8, version: []const u8, target: []const u8) !void {
        try self.printer.append("Modifying Manifest...\n");
        try Manifest.modifyManifest(name, version, target);
        self.printer.pop(1);
        try self.printer.append("Manifest Up to Date!\n");

        try self.printer.append("Switching to installed version...\n");
        try Path.modifyPath();
        self.printer.pop(1);
        try self.printer.append("Switched to installed version!\n");
    }
};
