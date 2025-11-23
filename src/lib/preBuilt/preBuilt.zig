const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;
const UtilsCompression = Utils.UtilsCompression;

/// Handles pre-built package operations (compress, decompress, delete)
pub const PreBuilt = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,
    compressor: UtilsCompression.Compressor,

    /// Initializes PreBuilt with compressor and ensures prebuilt folder exists
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !PreBuilt {
        if (!UtilsFs.checkDirExists(Constants.ROOT_ZEP_PREBUILT_FOLDER)) {
            try std.fs.cwd().makeDir(Constants.ROOT_ZEP_PREBUILT_FOLDER);
        }
        const compressor = UtilsCompression.Compressor.init(allocator, printer);

        return PreBuilt{
            .allocator = allocator,
            .printer = printer,
            .compressor = compressor,
        };
    }

    /// Extracts a pre-built package into the specified target path
    pub fn useBuilt(self: *PreBuilt, preBuiltName: []const u8, targetPath: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);

        if (!UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built does NOT exist!\n\n", .{}, .{});
            return;
        }

        try self.printer.append("Pre-Built found!\n", .{}, .{});

        if (!UtilsFs.checkDirExists(targetPath)) {
            try self.printer.append("Creating target path...\n", .{}, .{});
            try std.fs.cwd().makePath(targetPath);
            try self.printer.append("Created!\n\n", .{}, .{});
        }

        try self.printer.append("Decompressing {s} into {s}...\n", .{ path, targetPath }, .{});
        _ = try self.compressor.decompress(path, targetPath);

        try self.printer.append("Decompressed!\n\n", .{}, .{});
    }

    /// Compresses a folder into a pre-built package, overwriting if it exists
    pub fn buildBuilt(self: *PreBuilt, preBuiltName: []const u8, targetPath: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);

        if (UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built already exists! Overwriting it now...\n\n", .{}, .{});
            try std.fs.cwd().deleteFile(path);
        }

        try self.printer.append("Compressing {s} now...", .{targetPath}, .{});

        const isCompressed = try self.compressor.compress(targetPath, path);
        if (isCompressed) {
            try self.printer.append("Compressed!\n\n", .{}, .{});
        } else {
            try self.printer.append("Compression failed...\n\n", .{}, .{});
        }
    }

    /// Deletes a pre-built package if it exists
    pub fn deleteBuilt(self: *PreBuilt, preBuiltName: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);

        if (UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built found!\n", .{}, .{});
            try std.fs.cwd().deleteFile(path);
            try self.printer.append("Deleted.\n\n", .{}, .{});
        }
    }
};
