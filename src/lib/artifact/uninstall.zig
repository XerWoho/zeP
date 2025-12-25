const std = @import("std");

pub const ArtifactUninstaller = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const ArtifactSwitcher = @import("switch.zig");

const Context = @import("context");

/// Handles uninstalling Artifact versions
ctx: *Context,

pub fn init(ctx: *Context) ArtifactUninstaller {
    return ArtifactUninstaller{
        .ctx = ctx,
    };
}

pub fn deinit(_: *ArtifactUninstaller) void {
    // currently no deinit required
}

pub fn uninstall(self: *ArtifactUninstaller, path: []const u8) !void {
    try self.ctx.printer.append("Deleting Artifact version at path: {s}\n", .{path}, .{});

    // Recursively delete folder
    try Fs.deleteTreeIfExists(path);
    try self.ctx.printer.append("Artifact version deleted successfully.\n\n", .{}, .{ .color = .green });
}
