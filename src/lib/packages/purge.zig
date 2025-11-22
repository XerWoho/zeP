const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");
const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsManifest = Utils.UtilsManifest;
const UtilsFs = Utils.UtilsFs;

const Uninstall = @import("uninstall.zig");
const Init = @import("init.zig");

/// Handles purging of packages and cache/hashes
pub const Purger = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,
    printer: *UtilsPrinter.Printer,

    /// Initialize purger
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !Purger {
        const json = try UtilsJson.Json.init(allocator);
        return Purger{ .allocator = allocator, .json = json, .printer = printer };
    }

    /// Purge all installed packages
    pub fn purgePkgs(self: *Purger) !void {
        try self.printer.append("Purging packages...\n", .{}, .{});

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;

        if (!UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE)) {
            // Initialize zep.json if missing
            var initter = try Init.Init.init(self.allocator);
            try initter.commitInit();
            try self.printer.append("zep.json not initialized. Initializing...\n", .{}, .{});
            try self.printer.append("Nothing to uninstall.\n", .{}, .{});
            return;
        }
        var packageJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);

        const packageJsonValue = packageJson.value;
        defer packageJson.deinit();
        for (packageJsonValue.packages) |packageId| {
            var split = std.mem.splitScalar(u8, packageId, '@');
            const packageName = split.first();
            try self.printer.append(" > Uninstalling - {s}...\n", .{packageId}, .{ .verbosity = 0 });
            var uninstaller = try Uninstall.Uninstaller.init(self.allocator, packageName, self.printer);
            try uninstaller.uninstall();
            try self.printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = 32 });

            // small delay to avoid race conditions
            std.Thread.sleep(std.time.ms_per_s * 100);
        }

        try self.printer.append("\nPurged packages!\n", .{}, .{ .verbosity = 0, .color = 32 });
        Locales.VERBOSITY_MODE = previous_verbosity;
    }

    /// Purge caches
    pub fn purgeCache(self: *Purger) !void {
        try self.printer.append("Purging caches...\n", .{}, .{});
        if (UtilsFs.checkDirExists(Constants.ROOT_ZEP_ZEPPED_FOLDER)) {
            try std.fs.cwd().deleteTree(Constants.ROOT_ZEP_ZEPPED_FOLDER);
        }

        try self.printer.append("\nPurged cache!\n", .{}, .{ .verbosity = 0, .color = 32 });
    }
};
