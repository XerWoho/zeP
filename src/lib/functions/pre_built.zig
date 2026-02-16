const std = @import("std");

pub const PreBuilt = @This();

const Constants = @import("constants");
const Fs = @import("io").Fs;
const Context = @import("context");
const Errors = @import("errors");

/// Handles pre-built package operations (compress, decompress, delete)
ctx: *Context,

/// Initializes PreBuilt with compressor and ensures prebuilt folder exists
pub fn init(ctx: *Context) !PreBuilt {
    if (!Fs.existsDir(ctx.paths.prebuilt)) {
        try std.fs.cwd().makeDir(ctx.paths.prebuilt);
    }

    return PreBuilt{
        .ctx = ctx,
    };
}

/// Extracts a pre-built package into the specified target path
pub fn use(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) Errors.PreBuilt!void {
    self.ctx.logger.infof("Using Pre Built {s}", .{pre_built_name}, @src());

    const prebuilt_path = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}.tar.zstd",
        .{pre_built_name},
    );
    defer self.ctx.allocator.free(prebuilt_path);

    const path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            self.ctx.paths.prebuilt,
            prebuilt_path,
        },
    );
    defer self.ctx.allocator.free(path);

    if (!Fs.existsFile(path)) return Errors.PreBuilt.InvalidTarget;

    if (!Fs.existsDir(target_path)) std.fs.cwd().makePath(target_path) catch return Errors.PreBuilt.FileFailed;

    self.ctx.printer.append("Decompressing {s} into \"{s}\"\n", .{ path, target_path }, .{});
    self.ctx.compressor.decompress(path, target_path) catch return Errors.PreBuilt.DecompressingFailed;

    self.ctx.printer.append("Decompressed!\n\n", .{}, .{ .color = .green });
}

/// Compresses a folder into a pre-built package, overwriting if it exists
pub fn build(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) Errors.PreBuilt!void {
    self.ctx.logger.infof("New Pre Built {s}", .{pre_built_name}, @src());

    const path = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/{s}.tar.zstd",
        .{ self.ctx.paths.prebuilt, pre_built_name },
    );
    defer self.ctx.allocator.free(path);

    if (Fs.existsFile(path)) {
        self.ctx.printer.append("Pre-Built already exists! Overwriting it now...\n\n", .{}, .{});
        self.ctx.logger.info("Overwriting old pre-built...", @src());
        Fs.deleteFileIfExists(path) catch return Errors.PreBuilt.FileFailed;
    }

    self.ctx.printer.append("Compressing now...\n", .{}, .{});

    self.ctx.logger.info("Compressing Pre-Built...", @src());
    self.ctx.compressor.compress(target_path, path) catch return Errors.PreBuilt.CompressingFailed;
    self.ctx.printer.append("Compressed!\n\n", .{}, .{ .color = .green });
}

/// Deletes a pre-built package if it exists
pub fn delete(self: *PreBuilt, pre_built_name: []const u8) Errors.PreBuilt!void {
    self.ctx.logger.infof("Deleting Pre-Built {s}", .{pre_built_name}, @src());

    const exts = &[_][]const u8{ ".tar.zstd", ".zep" };

    for (exts) |ext| {
        const path = try std.fmt.allocPrint(
            self.ctx.allocator,
            "{s}/{s}{s}",
            .{ self.ctx.paths.prebuilt, pre_built_name, ext },
        );
        defer self.ctx.allocator.free(path);

        if (Fs.existsFile(path)) {
            self.ctx.printer.append("Pre-Built found!\n", .{}, .{ .color = .green });
            Fs.deleteFileIfExists(path) catch return Errors.PreBuilt.FileFailed;
            self.ctx.printer.append("Deleted.\n\n", .{}, .{});
            return;
        }
    }

    self.ctx.logger.infof("No Pre-Built named {s} was found...", .{pre_built_name}, @src());
    self.ctx.printer.append("Pre-Built not found!\n", .{}, .{ .color = .red });
}

/// List a pre-builts
pub fn list(self: *PreBuilt) Errors.PreBuilt!void {
    self.ctx.logger.info("Listing Pre Builts", @src());

    const dir = Fs.openDir(self.ctx.paths.prebuilt) catch return Errors.PreBuilt.DirFailed;
    var it = dir.iterate();
    var entries = false;
    while (it.next() catch return Errors.PreBuilt.IterFailed) |entry| {
        entries = true;
        const is_outdated = std.mem.endsWith(u8, entry.name, ".zep");
        if (is_outdated) {
            self.ctx.printer.append(
                " - {s} (OUTDATED)\n",
                .{entry.name},
                .{ .color = .bright_black },
            );
        } else {
            self.ctx.printer.append(
                " - {s}\n",
                .{entry.name},
                .{},
            );
        }
    }
    if (!entries) {
        self.ctx.printer.append("No prebuilts available!\n", .{}, .{});
    }
    self.ctx.printer.append("\n", .{}, .{});
}
