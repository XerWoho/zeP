const std = @import("std");

pub const Builder = @This();

const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");
const Context = @import("context");
const Errors = @import("errors");

const Fs = @import("io").Fs;

const Artifact = @import("../../lib/artifact/artifact.zig");

/// Initializes a Child Processor, and builds zig project
pub fn build(
    ctx: *Context,
    path: []const u8,
    zig_version: []const u8,
    options: struct {
        mute: bool = false,
    },
) Errors.Build![][]const u8 {
    ctx.logger.info("Building", @src());

    const lock = ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Build.ManifestFailed;
    defer lock.deinit();

    var target = lock.value.root.build.target;
    if (target.len == 0) {
        target = Constants.Default.resolveDefaultTarget();
    }

    var z = Artifact.init(ctx, .zig);
    defer z.deinit();

    const c = z.currentVersion() catch |err| {
        switch (err) {
            Errors.Artifact.InvalidVersion => return Errors.Build.InvalidVersion,
            Errors.Artifact.ManifestFailed => return Errors.Build.ManifestFailed,
            else => return Errors.Build.ZigFailed,
        }
    };
    errdefer {
        Locales.PRINTER_MUTE = true;
        z.switchVersion(c, target) catch {};
        Locales.PRINTER_MUTE = false;
    }

    if (!std.mem.eql(u8, c, zig_version)) {
        ctx.printer.append(
            "Switching to Zig Version: {s}\n",
            .{zig_version},
            .{
                .verbosity = 4,
            },
        );

        Locales.PRINTER_MUTE = true;
        z.switchVersion(zig_version, target) catch {
            Locales.PRINTER_MUTE = false;
            ctx.printer.append("Specified zig version [{s}], is not installed.\n", .{zig_version}, .{ .color = .red });
            ctx.printer.append("SUGGESTION:\n", .{}, .{ .color = .blue });
            ctx.printer.append(" - Install zig\n $ zep zig install {s}\n\n", .{zig_version}, .{});
            return Errors.Build.ZigFailed;
        };
        Locales.PRINTER_MUTE = false;
    }

    const execs = try std.fmt.allocPrint(
        ctx.allocator,
        "-Dtarget={s}",
        .{target},
    );
    defer ctx.allocator.free(execs);

    ctx.logger.info("Running Build...", @src());
    const args = [_][]const u8{
        "zig",
        "build",
        "-Doptimize=ReleaseSmall",
        execs,
        "-p",
        "zep-out/",
    };
    ctx.printer.append(
        "Executing: \n$ {s}\n\n",
        .{try std.mem.join(ctx.allocator, " ", &args)},
        .{ .color = .green },
    );

    var process = std.process.Child.init(&args, ctx.allocator);
    process.cwd = path;
    if (options.mute) {
        process.stdout_behavior = .Ignore;
        process.stderr_behavior = .Ignore;
    }

    const result = process.spawnAndWait() catch return Errors.Build.ProcessFailed;
    if (result.Exited > 0) return Errors.Build.ProcessFailed;
    ctx.logger.info("Build done...", @src());
    ctx.printer.append("Finished executing!\n\n", .{}, .{ .color = .green });

    const target_directory = try std.fs.path.join(ctx.allocator, &.{ "zep-out", "bin" });
    defer ctx.allocator.free(target_directory);

    const dir = Fs.openOrCreateDir(target_directory) catch return Errors.Build.InvalidBuild;
    var iter = dir.iterate();

    var entries = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 5);
    defer entries.deinit(ctx.allocator);
    while (iter.next() catch return Errors.Build.InvalidBuild) |entry| {
        try entries.append(ctx.allocator, entry.name);
    }

    if (entries.items.len == 0) {
        return Errors.Build.InvalidBuild;
    }

    var target_files = try ctx.allocator.alloc([]const u8, entries.items.len);
    for (entries.items, 0..) |entry, i| {
        const target_file = try std.fs.path.join(ctx.allocator, &.{ target_directory, entry });
        target_files[i] = target_file;
    }

    return target_files;
}
