const std = @import("std");

const Locales = @import("locales");
const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsPrinter = Utils.UtilsPrinter;

const Clear = @import("clear.zig");
const Uninstall = @import("uninstall.zig");
const Init = @import("init.zig");

/// Handles purging of packages and cache/fingerprints
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
        try self.printer.append("Purging packages...\n");
        Locales.VERBOSITY_MODE = 0;

        const pkgJsonOpt = try self.json.parsePkgJson();
        if (pkgJsonOpt == null) {
            // Initialize zep.json if missing
            var initter = try Init.Init.init(self.allocator);
            try initter.commitInit();
            try self.printer.append("zep.json not initialized. Initializing...\n");
            try self.printer.append("Nothing to uninstall.\n");
            return;
        }

        const pkgJson = pkgJsonOpt.?.value;
        defer pkgJsonOpt.?.deinit();

        for (pkgJson.packages) |pkgName| {
            var uninstaller = try Uninstall.Uninstaller.init(self.allocator, pkgName, self.printer);
            try uninstaller.uninstall();

            // small delay to avoid race conditions
            std.Thread.sleep(std.time.ms_per_s * 100);
        }

        Locales.VERBOSITY_MODE = 1;
    }

    /// Purge caches and fingerprints
    pub fn purgeCache(self: *Purger) !void {
        try self.printer.append("Purging caches and fingerprints...\n");
        Locales.VERBOSITY_MODE = 0;

        var clearer = Clear.Clearer.init();
        try clearer.clear(0);
        try clearer.clear(1);

        Locales.VERBOSITY_MODE = 1;
    }
};
