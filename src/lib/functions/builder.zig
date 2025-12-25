const std = @import("std");

pub const Builder = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Fs = @import("io").Fs;
const Context = @import("context");

/// Handles running a build
ctx: *Context,

/// Initializes Builder
pub fn init(ctx: *Context) !Builder {
    return Builder{
        .ctx = ctx,
    };
}

/// Initializes a Child Processor, and builds zig project
pub fn build(self: *Builder) !std.ArrayList([]u8) {
    const read_manifest = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer read_manifest.deinit();

    var target = read_manifest.value.build.target;
    if (target.len == 0) {
        target = Constants.Default.resolveDefaultTarget();
    }

    var buf: [64]u8 = undefined;
    const execs = try std.fmt.bufPrint(
        &buf,
        "-Dtarget={s}",
        .{target},
    );
    const args = [_][]const u8{ "zig", "build", "-Doptimize=ReleaseSmall", execs, "-p", "zep-out/" };
    try self.ctx.printer.append("\nExecuting: \n$ {s}!\n\n", .{try std.mem.join(self.ctx.allocator, " ", &args)}, .{ .color = .green });

    var process = std.process.Child.init(&args, self.ctx.allocator);
    _ = try process.spawnAndWait();
    try self.ctx.printer.append("\nFinished executing!\n", .{}, .{ .color = .green });

    const target_directory = try std.fs.path.join(self.ctx.allocator, &.{ "zep-out", "bin" });
    defer self.ctx.allocator.free(target_directory);

    const dir = try Fs.openOrCreateDir(target_directory);
    var iter = dir.iterate();

    var entries = try std.ArrayList([]const u8).initCapacity(self.ctx.allocator, 5);
    defer entries.deinit(self.ctx.allocator);
    while (try iter.next()) |entry| {
        try entries.append(self.ctx.allocator, entry.name);
    }

    if (entries.items.len == 0) {
        return error.NoFile;
    }

    var target_files = try std.ArrayList([]u8).initCapacity(self.ctx.allocator, 5);
    for (entries.items) |entry| {
        const target_file = try std.fs.path.join(self.ctx.allocator, &.{ target_directory, entry });
        try target_files.append(self.ctx.allocator, target_file);
    }
    return target_files;
}
