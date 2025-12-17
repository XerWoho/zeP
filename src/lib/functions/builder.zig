const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest.Manifest;

/// Handles running a build
pub const Builder = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    manifest: *Manifest,

    /// Initializes Builder
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        manifest: *Manifest,
    ) !Builder {
        return Builder{
            .allocator = allocator,
            .printer = printer,
            .manifest = manifest,
        };
    }

    /// Initializes a Child Processor, and builds zig project
    pub fn build(self: *Builder) !std.ArrayList([]u8) {
        const read_manifest = try self.manifest.readManifest(
            Structs.ZepFiles.PackageJsonStruct,
            Constants.Extras.package_files.manifest,
        );
        defer read_manifest.deinit();

        var target = read_manifest.value.build.target;
        if (target.len == 0) {
            target = if (builtin.os.tag == .windows) Constants.Default.default_targets.windows else Constants.Default.default_targets.linux;
        }

        var buf: [64]u8 = undefined;
        const execs = try std.fmt.bufPrint(
            &buf,
            "-Dtarget={s}",
            .{target},
        );
        const args = [_][]const u8{ "zig", "build", "-Doptimize=ReleaseSmall", execs, "-p", "zep-out/" };
        try self.printer.append("\nExecuting: \n$ {s}!\n\n", .{try std.mem.join(self.allocator, " ", &args)}, .{ .color = .green });

        var process = std.process.Child.init(&args, self.allocator);
        _ = process.spawnAndWait() catch |err| {
            switch (err) {
                error.FileNotFound => {
                    try self.printer.append("Zig is not installed!\nExiting!\n\n", .{}, .{ .color = .red });
                    try self.printer.append("\nSUGGESTION:\n", .{}, .{ .color = .blue });
                    try self.printer.append(" - Install zig\n $ zep zig install <version>\n\n", .{}, .{});
                    std.process.exit(0);
                    return;
                },
                else => {
                    try self.printer.append("\nZig building failed!\nExiting.\n\n", .{}, .{ .color = .red });
                    std.process.exit(0);
                    return;
                },
            }
        };
        try self.printer.append("\nFinished executing!\n", .{}, .{ .color = .green });

        const target_directory = try std.fs.path.join(self.allocator, &.{ "zep-out", "bin" });
        defer self.allocator.free(target_directory);

        const dir = try Fs.openOrCreateDir(target_directory);
        var iter = dir.iterate();

        var entries = try std.ArrayList([]const u8).initCapacity(self.allocator, 5);
        defer entries.deinit(self.allocator);
        while (try iter.next()) |entry| {
            try entries.append(self.allocator, entry.name);
        }

        if (entries.items.len == 0) {
            return error.NoFile;
        }

        var target_files = try std.ArrayList([]u8).initCapacity(self.allocator, 5);
        for (entries.items) |entry| {
            const target_file = try std.fs.path.join(self.allocator, &.{ target_directory, entry });
            try target_files.append(self.allocator, target_file);
        }
        return target_files;
    }
};
