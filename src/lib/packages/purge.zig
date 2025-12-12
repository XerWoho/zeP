const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");

const Fs = @import("io").Fs;
const Json = @import("core").Json.Json;
const Manifest = @import("core").Manifest;
const Printer = @import("cli").Printer;

const Uninstaller = @import("uninstall.zig").Uninstaller;
const Init = @import("init.zig").Init;

pub fn purge(
    allocator: std.mem.Allocator,
    printer: *Printer,
    json: *Json,
    paths: *Constants.Paths.Paths,
) !void {
    try printer.append("Purging packages...\n", .{}, .{});

    const previous_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
        // Initialize zep.json if missing
        try printer.append("zep.json not initialized.\n", .{}, .{});
        var initer = try Init.init(
            allocator,
            printer,
            json,
            true,
        );
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
        var uninstaller = try Uninstaller.init(
            allocator,
            printer,
            json,
            paths,
            package_name,
        );
        uninstaller.uninstall() catch {
            try printer.append(" >> failed!\n", .{}, .{ .verbosity = 0, .color = .red });
            std.Thread.sleep(std.time.ms_per_s * 100);
            continue;
        };

        try printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });

        // small delay to avoid race conditions
        std.Thread.sleep(std.time.ms_per_s * 100);
    }

    try printer.append("\nPurged packages!\n", .{}, .{ .verbosity = 0, .color = .green });
    Locales.VERBOSITY_MODE = previous_verbosity;
}
