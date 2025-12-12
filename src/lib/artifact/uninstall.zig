const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");
const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const Manifest = @import("core").Manifest;
const ArtifactSwitcher = @import("switch.zig").ArtifactSwitcher;

/// Handles uninstalling Artifact versions
pub const ArtifactUninstaller = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !ArtifactUninstaller {
        return ArtifactUninstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    pub fn deinit(_: *ArtifactUninstaller) void {
        // currently no deinit required
    }

    pub fn uninstall(self: *ArtifactUninstaller, path: []const u8) !void {
        try self.printer.append("Deleting Artifact version at path: {s}\n", .{path}, .{});

        // Recursively delete folder
        try Fs.deleteTreeIfExists(path);
        try self.printer.append("Artifact version deleted successfully.\n\n", .{}, .{ .color = .green });
    }
};
