const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;

const Uninstaller = @import("uninstall.zig");

const Context = @import("context");
pub fn purge(ctx: *Context) !void {
    ctx.logger.info("Purging Packages", @src());
    const lock = try ctx.manifest.readManifest(Structs.ZepFiles.Lock, Constants.Default.package_files.lock);
    defer lock.deinit();

    ctx.printer.append("This project contains {d} packages.\n", .{lock.value.packages.len}, .{});
    const answer = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        "Purge them all? (y/N) ",
        .{},
    );
    if (answer.len == 0 or
        std.mem.startsWith(u8, answer, "n") or
        std.mem.startsWith(u8, answer, "N"))
    {
        ctx.printer.append("\nOk.\n", .{}, .{});
        return;
    }

    ctx.printer.append("\nPurging packages...\n", .{}, .{});

    Locales.PRINTER_MUTE = true;
    defer Locales.PRINTER_MUTE = false;
    if (!Fs.existsFile(Constants.Default.package_files.lock)) {
        ctx.printer.append("Nothing to uninstall.\n", .{}, .{});
        return;
    }

    var uninstaller = Uninstaller.init(
        ctx,
    );
    defer uninstaller.deinit();

    for (lock.value.root.packages) |package_id| {
        ctx.printer.append(" > Uninstalling - {s} ", .{package_id}, .{ .verbosity = 0 });

        var split = std.mem.splitScalar(u8, package_id, '@');
        const name = split.first();
        uninstaller.uninstallPackage(name) catch {
            ctx.printer.append(" >> failed!\n", .{}, .{ .verbosity = 0, .color = .red });
            std.Thread.sleep(std.time.ms_per_s * 100);
            continue;
        };

        ctx.printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });

        // small delay to avoid race conditions
        std.Thread.sleep(std.time.ms_per_s * 100);
    }

    ctx.printer.append("\nPurged packages!\n", .{}, .{ .verbosity = 0, .color = .green });
}
