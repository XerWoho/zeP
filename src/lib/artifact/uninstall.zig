const std = @import("std");

pub const ArtifactUninstaller = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const ArtifactSwitcher = @import("switch.zig");

const Context = @import("context");
const Errors = @import("errors");

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

/// Uninstall selected path
/// of any artifact. This is
/// a wrapper for logging
/// and printing the uninstallation
/// progress, it is only deleting
/// the path tree specified.
pub fn uninstall(self: *ArtifactUninstaller, path: []const u8) Errors.Artifact!void {
    self.ctx.logger.infof("Uninstalling {s}", .{path}, @src());

    self.ctx.printer.append("Deleting Artifact version at path: {s}\n", .{path}, .{});

    // Recursively delete folder
    Fs.deleteTreeIfExists(path) catch return Errors.Artifact.DeleteFailed;
    self.ctx.printer.append("Artifact version deleted successfully.\n\n", .{}, .{ .color = .green });
}
