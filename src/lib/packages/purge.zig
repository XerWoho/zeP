const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Locales = @import("locales");

const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json.Json;
const Printer = @import("cli").Printer;

const Uninstaller = @import("uninstall.zig").Uninstaller;
const Init = @import("init.zig").Init;

/// Handles purging of packages and cache/hashes
pub const Purger = struct {
    allocator: std.mem.Allocator,
    json: Json,
    printer: *Printer,

    /// Initialize purger
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !Purger {
        const json = try Json.init(allocator);
        return Purger{ .allocator = allocator, .json = json, .printer = printer };
    }

    /// Purge all installed packages
    pub fn purgePkgs(self: *Purger) !void {
        try self.printer.append("Purging packages...\n", .{}, .{});

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;

        if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
            // Initialize zep.json if missing
            try self.printer.append("zep.json not initialized.\n", .{}, .{});
            var initter = try Init.init(self.allocator, self.printer, true);
            try initter.commitInit();
            try self.printer.append("Nothing to uninstall.\n", .{}, .{});
            return;
        }
        var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer package_json.deinit();

        for (package_json.value.packages) |package_id| {
            var split = std.mem.splitScalar(u8, package_id, '@');
            const package_name = split.first();
            try self.printer.append(" > Uninstalling - {s}...\n", .{package_id}, .{ .verbosity = 0 });
            var uninstaller = try Uninstaller.init(self.allocator, package_name, self.printer);
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

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        if (Fs.existsDir(paths.zepped)) {
            try Fs.deleteTreeIfExists(paths.zepped);
        }

        try self.printer.append("\nPurged cache!\n", .{}, .{ .verbosity = 0, .color = 32 });
    }
};
