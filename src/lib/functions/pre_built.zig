const std = @import("std");

const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;
const Compressor = @import("core").Compression.Compressor;

/// Handles pre-built package operations (compress, decompress, delete)
pub const PreBuilt = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    compressor: Compressor,

    /// Initializes PreBuilt with compressor and ensures prebuilt folder exists
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !PreBuilt {
        var paths = try Constants.Paths.paths(allocator);
        defer paths.deinit();

        if (!Fs.existsDir(paths.prebuilt)) {
            try std.fs.cwd().makeDir(paths.prebuilt);
        }
        const compressor = Compressor.init(allocator, printer);

        return PreBuilt{
            .allocator = allocator,
            .printer = printer,
            .compressor = compressor,
        };
    }

    /// Extracts a pre-built package into the specified target path
    pub fn use(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ paths.prebuilt, pre_built_name });
        defer self.allocator.free(path);

        if (!Fs.existsFile(path)) {
            try self.printer.append("Pre-Built does NOT exist!\n\n", .{}, .{});
            return;
        }

        try self.printer.append("Pre-Built found!\n", .{}, .{});

        if (!Fs.existsDir(target_path)) {
            try self.printer.append("Creating target path...\n", .{}, .{});
            try std.fs.cwd().makePath(target_path);
            try self.printer.append("Created!\n\n", .{}, .{});
        }

        try self.printer.append("Decompressing {s} into {s}...\n", .{ path, target_path }, .{});
        _ = try self.compressor.decompress(path, target_path);

        try self.printer.append("Decompressed!\n\n", .{}, .{});
    }

    /// Compresses a folder into a pre-built package, overwriting if it exists
    pub fn build(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ paths.prebuilt, pre_built_name });
        defer self.allocator.free(path);

        if (Fs.existsFile(path)) {
            try self.printer.append("Pre-Built already exists! Overwriting it now...\n\n", .{}, .{});
            try Fs.deleteFileIfExists(path);
        }

        try self.printer.append("Compressing {s} now...", .{target_path}, .{});

        const is_compressed = try self.compressor.compress(target_path, path);
        if (is_compressed) {
            try self.printer.append("Compressed!\n\n", .{}, .{});
        } else {
            try self.printer.append("Compression failed...\n\n", .{}, .{});
        }
    }

    /// Deletes a pre-built package if it exists
    pub fn delete(self: *PreBuilt, pre_built_name: []const u8) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ paths.prebuilt, pre_built_name });
        defer self.allocator.free(path);

        if (Fs.existsFile(path)) {
            try self.printer.append("Pre-Built found!\n", .{}, .{});
            try Fs.deleteFileIfExists(path);
            try self.printer.append("Deleted.\n\n", .{}, .{});
        }
    }

    /// List a pre-builts
    pub fn list(self: *PreBuilt) !void {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const dir = try Fs.openDir(paths.prebuilt);
        var it = dir.iterate();
        var entries = false;
        while (try it.next()) |entry| {
            entries = true;
            try self.printer.append(" - {s}\n", .{entry.name}, .{});
        }
        if (!entries) {
            try self.printer.append("No prebuilts available!\n", .{}, .{ .color = 31 });
        }
        try self.printer.append("\n", .{}, .{});
    }
};
