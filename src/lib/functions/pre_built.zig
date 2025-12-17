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
    paths: *Constants.Paths.Paths,

    /// Initializes PreBuilt with compressor and ensures prebuilt folder exists
    pub fn init(allocator: std.mem.Allocator, printer: *Printer, paths: *Constants.Paths.Paths) !PreBuilt {
        if (!Fs.existsDir(paths.prebuilt)) {
            try std.fs.cwd().makeDir(paths.prebuilt);
        }
        const compressor = try Compressor.init(
            allocator,
            printer,
            paths,
        );

        return PreBuilt{
            .allocator = allocator,
            .printer = printer,
            .compressor = compressor,
            .paths = paths,
        };
    }

    /// Extracts a pre-built package into the specified target path
    pub fn use(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.zstd",
            .{ self.paths.prebuilt, pre_built_name },
        );

        if (!Fs.existsFile(path)) {
            try self.printer.append("Pre-Built does NOT exist!\n\n", .{}, .{ .color = .red });
            return;
        }

        try self.printer.append("Pre-Built found!\n", .{}, .{ .color = .green });

        if (!Fs.existsDir(target_path)) {
            try std.fs.cwd().makePath(target_path);
        }

        try self.printer.append("Decompressing {s} into {s}...\n", .{ path, target_path }, .{});
        _ = try self.compressor.decompress(path, target_path);

        try self.printer.append("Decompressed!\n\n", .{}, .{ .color = .green });
    }

    /// Compresses a folder into a pre-built package, overwriting if it exists
    pub fn build(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.tar.zstd",
            .{ self.paths.prebuilt, pre_built_name },
        );

        if (Fs.existsFile(path)) {
            try self.printer.append("Pre-Built already exists! Overwriting it now...\n\n", .{}, .{});
            try Fs.deleteFileIfExists(path);
        }

        try self.printer.append("Compressing now...", .{}, .{});

        const is_compressed = try self.compressor.compress(target_path, path);
        if (is_compressed) {
            try self.printer.append("Compressed!\n\n", .{}, .{ .color = .green });
        } else {
            try self.printer.append("Compression failed...\n\n", .{}, .{ .color = .red });
        }
    }

    /// Deletes a pre-built package if it exists
    pub fn delete(self: *PreBuilt, pre_built_name: []const u8) !void {
        var buf: [256]u8 = undefined;
        const exts = &[_][]const u8{ ".tar.zstd", ".zep" };

        for (exts) |ext| {
            const path = try std.fmt.bufPrint(&buf, "{s}/{s}{s}", .{ self.paths.prebuilt, pre_built_name, ext });
            if (Fs.existsFile(path)) {
                try self.printer.append("Pre-Built found!\n", .{}, .{ .color = .green });
                try Fs.deleteFileIfExists(path);
                try self.printer.append("Deleted.\n\n", .{}, .{});
                return;
            }
        }

        try self.printer.append("Pre-Built not found!\n", .{}, .{ .color = .red });
    }

    /// List a pre-builts
    pub fn list(self: *PreBuilt) !void {
        const dir = try Fs.openDir(self.paths.prebuilt);
        var it = dir.iterate();
        var entries = false;
        while (try it.next()) |entry| {
            entries = true;
            const is_outdated = std.mem.endsWith(u8, entry.name, ".zep");
            if (is_outdated) {
                try self.printer.append(
                    " - {s} (OUTDATED)\n",
                    .{entry.name},
                    .{ .color = .bright_black },
                );
            } else {
                try self.printer.append(
                    " - {s}\n",
                    .{entry.name},
                    .{},
                );
            }
        }
        if (!entries) {
            try self.printer.append("No prebuilts available!\n", .{}, .{});
        }
        try self.printer.append("\n", .{}, .{});
    }
};
