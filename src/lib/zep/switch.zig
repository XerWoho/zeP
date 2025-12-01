const std = @import("std");
const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

/// Handles switching between installed Zep versions
pub const ZepSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ZepSwitcher
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !ZepSwitcher {
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
        try self.printer.append("Modifying Manifest...\n", .{}, .{});

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const path = try std.fs.path.join(self.allocator, &.{ paths.zep_root, "v", version });
        defer self.allocator.free(path);
        Manifest.writeManifest(
            Structs.Manifests.ZepManifest,
            self.allocator,
            paths.zep_manifest,
            Structs.Manifests.ZepManifest{
                .version = version,
                .path = path,
            },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Manifest up to date!\n", .{}, .{ .color = 32 });

        // Update system PATH to point to new version
        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink() catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };
        try self.printer.append("Switched to installed version successfully!\n", .{}, .{ .color = 32 });
    }
};
