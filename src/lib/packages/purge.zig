const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");

const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;
const Printer = @import("cli").Printer;

const Uninstaller = @import("uninstall.zig").Uninstaller;
const Init = @import("init.zig").Init;

pub fn purge(printer: *Printer, allocator: std.mem.Allocator) !void {
    try printer.append("Purging packages...\n", .{}, .{});

    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
        // Initialize zep.json if missing
        try printer.append("zep.json not initialized.\n", .{}, .{});
        var initer = try Init.init(allocator, printer, true);
        try initer.commitInit();
        try printer.append("Nothing to uninstall.\n", .{}, .{});
        return;
    }
    var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);
    defer package_json.deinit();

    for (package_json.value.packages) |package_id| {
        var split = std.mem.splitScalar(u8, package_id, '@');
        const package_name = split.first();
        try printer.append(" > Uninstalling - {s}...\n", .{package_id}, .{ .verbosity = 0 });
        var uninstaller = try Uninstaller.init(allocator, package_name, printer);
        uninstaller.uninstall() catch {
            try printer.append(" >> failed!\n", .{}, .{ .verbosity = 0, .color = 31 });
            std.Thread.sleep(std.time.ms_per_s * 100);
            continue;
        };

        try printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = 32 });

        // small delay to avoid race conditions
        std.Thread.sleep(std.time.ms_per_s * 100);
    }

    try printer.append("\nPurged packages!\n", .{}, .{ .verbosity = 0, .color = 32 });
    Locales.VERBOSITY_MODE = previous_verbosity;
}
