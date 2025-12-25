const std = @import("std");

const Constants = @import("constants");

const Fs = @import("io").Fs;

const Context = @import("context").Context;

/// Handles pre-built package operations (compress, decompress, delete)
pub const PreBuilt = struct {
    ctx: *Context,

    /// Initializes PreBuilt with compressor and ensures prebuilt folder exists
    pub fn init(
        ctx: *Context,
    ) !PreBuilt {
        if (!Fs.existsDir(ctx.paths.prebuilt)) {
            try std.fs.cwd().makeDir(ctx.paths.prebuilt);
        }

        return PreBuilt{
            .ctx = ctx,
        };
    }

    /// Extracts a pre-built package into the specified target path
    pub fn use(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var buf: [256]u8 = undefined;
        const prebuilt_path = try std.fmt.bufPrint(
            &buf,
            "{s}.tar.zstd",
            .{pre_built_name},
        );
        const path = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                self.ctx.paths.prebuilt,
                prebuilt_path,
            },
        );
        defer self.ctx.allocator.free(path);

        if (!Fs.existsFile(path)) {
            try self.ctx.printer.append("Pre-Built does NOT exist!\n\n", .{}, .{ .color = .red });
            return;
        }

        try self.ctx.printer.append("Pre-Built found!\n", .{}, .{ .color = .green });

        if (!Fs.existsDir(target_path)) {
            try std.fs.cwd().makePath(target_path);
        }

        try self.ctx.printer.append("Decompressing {s} into \"{s}\"\n", .{ path, target_path }, .{});
        try self.ctx.compressor.decompress(path, target_path);

        try self.ctx.printer.append("Decompressed!\n\n", .{}, .{ .color = .green });
    }

    /// Compresses a folder into a pre-built package, overwriting if it exists
    pub fn build(self: *PreBuilt, pre_built_name: []const u8, target_path: []const u8) !void {
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.tar.zstd",
            .{ self.ctx.paths.prebuilt, pre_built_name },
        );

        if (Fs.existsFile(path)) {
            try self.ctx.printer.append("Pre-Built already exists! Overwriting it now...\n\n", .{}, .{});
            try Fs.deleteFileIfExists(path);
        }

        try self.ctx.printer.append("Compressing now...\n", .{}, .{});

        const is_compressed = try self.ctx.compressor.compress(target_path, path);
        if (is_compressed) {
            try self.ctx.printer.append("Compressed!\n\n", .{}, .{ .color = .green });
        } else {
            try self.ctx.printer.append("Compression failed...\n\n", .{}, .{ .color = .red });
        }
    }

    /// Deletes a pre-built package if it exists
    pub fn delete(self: *PreBuilt, pre_built_name: []const u8) !void {
        var buf: [256]u8 = undefined;
        const exts = &[_][]const u8{ ".tar.zstd", ".zep" };

        for (exts) |ext| {
            const path = try std.fmt.bufPrint(&buf, "{s}/{s}{s}", .{ self.ctx.paths.prebuilt, pre_built_name, ext });
            if (Fs.existsFile(path)) {
                try self.ctx.printer.append("Pre-Built found!\n", .{}, .{ .color = .green });
                try Fs.deleteFileIfExists(path);
                try self.ctx.printer.append("Deleted.\n\n", .{}, .{});
                return;
            }
        }

        try self.ctx.printer.append("Pre-Built not found!\n", .{}, .{ .color = .red });
    }

    /// List a pre-builts
    pub fn list(self: *PreBuilt) !void {
        const dir = try Fs.openDir(self.ctx.paths.prebuilt);
        var it = dir.iterate();
        var entries = false;
        while (try it.next()) |entry| {
            entries = true;
            const is_outdated = std.mem.endsWith(u8, entry.name, ".zep");
            if (is_outdated) {
                try self.ctx.printer.append(
                    " - {s} (OUTDATED)\n",
                    .{entry.name},
                    .{ .color = .bright_black },
                );
            } else {
                try self.ctx.printer.append(
                    " - {s}\n",
                    .{entry.name},
                    .{},
                );
            }
        }
        if (!entries) {
            try self.ctx.printer.append("No prebuilts available!\n", .{}, .{});
        }
        try self.ctx.printer.append("\n", .{}, .{});
    }
};
