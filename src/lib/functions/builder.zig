const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest;

/// Handles running a build
pub const Builder = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    /// Initializes Builder
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !Builder {
        return Builder{
            .allocator = allocator,
            .printer = printer,
        };
    }

    /// Initializes a Child Processor, and builds zig project
    pub fn build(self: *Builder) ![]u8 {
        const read_manifest = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer read_manifest.deinit();

        const execs = try std.fmt.allocPrint(self.allocator, "-Dtarget={s}", .{read_manifest.value.build.target});
        defer self.allocator.free(execs);
        const args = [_][]const u8{ "zig", "build", "-Doptimize=ReleaseSmall", execs, "-p", "zep-out/" };

        try self.printer.append("\nExecuting: \n$ {s}!\n\n", .{try std.mem.join(self.allocator, " ", &args)}, .{ .color = 32 });

        var process = std.process.Child.init(&args, self.allocator);
        _ = process.spawnAndWait() catch {};
        try self.printer.append("\nFinished executing!\n", .{}, .{ .color = 32 });

        const target_directory = try std.fs.path.join(self.allocator, &.{ "zep-out", "bin" });
        defer self.allocator.free(target_directory);

        const dir = try Fs.openOrCreateDir(target_directory);
        var iter = dir.iterate();

        var entries = std.ArrayList([]const u8).init(self.allocator);
        defer entries.deinit();
        while (try iter.next()) |entry| {
            try entries.append(entry.name);
        }

        const target_file = try std.fs.path.join(self.allocator, &.{ target_directory, entries.items[0] });
        return target_file;
    }
};
