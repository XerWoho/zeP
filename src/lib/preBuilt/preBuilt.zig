const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsFs = Utils.UtilsFs;
const UtilsCompression = Utils.UtilsCompression;

pub const PreBuilt = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,
    compressor: UtilsCompression.Compressor,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !PreBuilt {
        if (!try UtilsFs.checkDirExists(Constants.ROOT_ZEP_PREBUILT_FOLDER)) {
            try std.fs.cwd().makeDir(Constants.ROOT_ZEP_PREBUILT_FOLDER);
        }
        const compressor = try UtilsCompression.Compressor.init(allocator, printer);

        return PreBuilt{ .allocator = allocator, .printer = printer, .compressor = compressor };
    }

    pub fn getBuilt(self: *PreBuilt, preBuiltName: []const u8, targetPath: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);

        if (!try UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built does NOT exist!\n\n");
            return;
        }

        try self.printer.append("Pre-Built found!\n");
        if (!try UtilsFs.checkDirExists(targetPath)) {
            try self.printer.append("Creating target path...\n");
            try std.fs.cwd().makePath(targetPath);
            try self.printer.append("Created!\n\n");
        }

        try self.printer.append("Decompressing ");
        try self.printer.append(path);
        try self.printer.append(" into ");
        try self.printer.append(targetPath);
        try self.printer.append(" ...\n");
        _ = try self.compressor.decompress(path, targetPath);
        try self.printer.append("Decompressed!\n\n");
    }

    pub fn setBuilt(self: *PreBuilt, preBuiltName: []const u8, targetPath: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);

        if (try UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built already exists!\nOverwriting it now...\n\n");
            try std.fs.cwd().deleteFile(path);
        }

        try self.printer.append("Compressing ");
        try self.printer.append(targetPath);
        try self.printer.append(" now...\n");
        try self.compressor.compress(targetPath, path);
        try self.printer.append("Compressed!\n\n");
    }

    pub fn delBuilt(self: *PreBuilt, preBuiltName: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.zep", .{ Constants.ROOT_ZEP_PREBUILT_FOLDER, preBuiltName });
        defer self.allocator.free(path);
        if (try UtilsFs.checkFileExists(path)) {
            try self.printer.append("Pre-Built found!\n");
            try std.fs.cwd().deleteFile(path);
            try self.printer.append("Deleted.\n\n");
        }
    }
};
