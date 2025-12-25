const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");

const Fs = @import("io").Fs;

const Uninstaller = @import("uninstall.zig").Uninstaller;
const Init = @import("init.zig").Init;

const Context = @import("context").Context;
pub fn purge(ctx: *Context) !void {
    try ctx.printer.append("Purging packages...\n", .{}, .{});

    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
        // Initialize zep.ctx.json if missing
        try ctx.printer.append("zep.ctx.json not initialized.\n", .{}, .{});
        var initer = try Init.init(
            ctx,
            true,
        );
        try initer.commitInit();
        try ctx.printer.append("Nothing to uninstall.\n", .{}, .{});
        return;
    }
    var package_json = try ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer package_json.deinit();

    var uninstaller = Uninstaller.init(
        ctx,
    );
    for (package_json.value.packages) |package_id| {
        var split = std.mem.splitScalar(u8, package_id, '@');
        const package_name = split.first();
        try ctx.printer.append(" > Uninstalling - {s}...\n", .{package_id}, .{ .verbosity = 0 });
        uninstaller.uninstall(package_name) catch {
            try ctx.printer.append(" >> failed!\n", .{}, .{ .verbosity = 0, .color = .red });
            std.Thread.sleep(std.time.ms_per_s * 100);
            continue;
        };

        try ctx.printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });

        // small delay to avoid race conditions
        std.Thread.sleep(std.time.ms_per_s * 100);
    }

    try ctx.printer.append("\nPurged packages!\n", .{}, .{ .verbosity = 0, .color = .green });
    Locales.VERBOSITY_MODE = previous_verbosity;
}
