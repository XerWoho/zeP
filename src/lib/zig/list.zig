const std = @import("std");
const Manifest = @import("lib/manifest.zig");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;

pub const ZigLister = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *UtilsPrinter.Printer,
    ) !ZigLister {
        return ZigLister{ .allocator = allocator, .printer = printer };
    }

    pub fn deinit(self: *ZigLister) void {
        _ = self;
        defer {
            // self.printer.deinit();
        }
    }

    pub fn listVersions(self: *ZigLister) !void {
        try self.printer.append("\nAvailable Versions;\n");
        const path = try std.fmt.allocPrint(self.allocator, "{s}/d/", .{Constants.ROOT_ZEP_ZIG_FOLDER});
        defer self.allocator.free(path);
        if (!try UtilsFs.checkDirExists(path)) {
            try self.printer.append("No versions!\n\n");
            return;
        }

        const manifest = try Manifest.getManifest();
        defer manifest.deinit();

        const dir = try std.fs.cwd().openDir(path, std.fs.Dir.OpenDirOptions{ .iterate = true });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            const name = try self.allocator.dupe(u8, entry.name);
            try self.printer.append(name);
            if (std.mem.containsAtLeast(u8, manifest.value.path, 1, name)) {
                try self.printer.append(" (in-use)");
            }
            try self.printer.append("\n");
        }
        try self.printer.append("\n");
    }
};
