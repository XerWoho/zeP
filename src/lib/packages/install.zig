const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("core").Json.Json;
const Compressor = @import("core").Compression.Compressor;
const Package = @import("core").Package.Package;
const Injector = @import("core").Injector.Injector;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

const Cacher = @import("lib/cache.zig").Cacher;
const Downloader = @import("lib/download.zig").Downloader;
const Uninstaller = @import("uninstall.zig").Uninstaller;

pub const Installer = struct {
    allocator: std.mem.Allocator,
    json: Json,
    package: Package,
    downloader: Downloader,
    cacher: Cacher,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *Printer, package_name: ?[]const u8, package_version_target: ?[]const u8) !Installer {
        if (package_name == null) {
            const previous_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;

            try printer.append("Installing all packages...\n", .{}, .{ .verbosity = 0 });

            try installAll(allocator, printer);

            Locales.VERBOSITY_MODE = previous_verbosity;
            std.process.exit(0);
            return .NoPackageSpecified;
        }

        const package = try Package.init(allocator, package_name.?, package_version_target, printer) orelse {
            std.process.exit(0);
            return .PackageNotFound;
        };

        const cacher = try Cacher.init(allocator, package, printer);
        const downloader = try Downloader.init(allocator, package, cacher, printer);
        const json = try Json.init(allocator);

        return Installer{
            .json = json,
            .allocator = allocator,
            .package = package,
            .downloader = downloader,
            .cacher = cacher,
            .printer = printer,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cacher.deinit();
        self.downloader.deinit();
        self.package.deinit();
    }

    pub fn install(self: *Installer) !void {
        const package = self.package;
        const parsed = package.package;

        const lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer lock.deinit();
        if (!std.mem.containsAtLeast(u8, parsed.zig_version, 1, lock.value.root.zig_version)) {
            try self.printer.append("WARNING: ", .{}, .{ .color = 31 });
            try self.printer.append("ZIG VERSIONS ARE NOT MATCHING!\n", .{}, .{ .color = 34 });
            try self.printer.append("{s} Zig Version: {s}\n", .{ package.id, parsed.zig_version }, .{});
            try self.printer.append("Your Zig Version: {s}\n\n", .{lock.value.root.zig_version}, .{});
        }

        for (lock.value.packages) |lockPackage| {
            if (std.mem.startsWith(u8, lockPackage.name, self.package.package_name)) {
                if (std.mem.eql(u8, lockPackage.name, self.package.id)) {
                    try self.setPackage();
                    return error.AlreadyInstalled;
                }

                std.debug.print("MATCHED UNINSTALLING", .{});
                const previous_verbosity = Locales.VERBOSITY_MODE;
                Locales.VERBOSITY_MODE = 0;

                var uninstaller = try Uninstaller.init(
                    self.allocator,
                    self.package.package_name,
                    self.printer,
                );

                try uninstaller.uninstall();
                Locales.VERBOSITY_MODE = previous_verbosity;
            }
        }

        try self.printer.append("Downloading Package...\n", .{}, .{});
        try self.downloader.downloadPackage(parsed.url);

        try self.printer.append("\nChecking hash...\n", .{}, .{});
        if (std.mem.eql(u8, package.package_hash, parsed.sha256sum)) {
            try self.printer.append("HASH IDENTICAL!\n", .{}, .{});
        } else {
            try self.package.deletePackage(true);
            try self.cacher.deletePackageFromCache();
            return error.HashMismatch;
        }

        try self.printer.append("\nChecking Caching...\n", .{}, .{});
        const is_package_cached = try self.cacher.isPackageCached();
        if (!is_package_cached) {
            try self.printer.append("\nCaching...\n", .{}, .{});

            try self.cacher.cachePackage();
            try self.printer.append("PACKAGE CACHED!\n\n", .{}, .{});
        }
        try self.printer.append("PACKAGE ALREADY CACHED! SKIPPING CACHING!\n\n", .{}, .{});

        try self.setPackage();
        try self.printer.append("Successfully installed - {s}\n\n", .{package.package_name}, .{ .color = 32 });
    }

    fn setPackage(self: *Installer) !void {
        try self.addPackageToJson();
        const package = self.package;

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        var injector = Injector.init(self.allocator, package.package_name, self.printer);
        try injector.initInjector();

        // symbolic link
        const target_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}@{s}", .{ paths.pkg_root, package.package_name, package.package_version });
        defer self.allocator.free(target_path);

        const relative_symbolic_link_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.Extras.package_files.zep_folder, package.package_name });
        Fs.deleteTreeIfExists(relative_symbolic_link_path) catch {};
        Fs.deleteFileIfExists(relative_symbolic_link_path) catch {};
        defer self.allocator.free(relative_symbolic_link_path);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const absolute_symbolic_link_path = try std.fs.path.join(self.allocator, &.{ cwd, relative_symbolic_link_path });
        defer self.allocator.free(absolute_symbolic_link_path);
        try std.fs.cwd().symLink(target_path, relative_symbolic_link_path, .{ .is_directory = true });
        Manifest.addPathToManifest(
            &self.json,
            self.package.id,
            absolute_symbolic_link_path,
        ) catch {
            try self.printer.append("Adding to manifest failed!\n", .{}, .{ .color = 31 });
        };
    }

    fn addPackageToJson(self: *Installer) !void {
        var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        var lock_json = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);

        defer package_json.deinit();
        defer lock_json.deinit();
        try self.package.manifestAdd(&package_json.value);
        try self.package.lockAdd(&lock_json.value);
    }
};

fn installAll(allocator: std.mem.Allocator, printer: *Printer) anyerror!void {
    var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);

    defer package_json.deinit();
    for (package_json.value.packages) |package_id| {
        try printer.append(" > Installing - {s}...\n", .{package_id}, .{ .verbosity = 0 });

        var package_split = std.mem.splitScalar(u8, package_id, '@');
        const package_name = package_split.first();
        const package_version = package_split.next();
        var installer = try Installer.init(allocator, printer, package_name, package_version);
        installer.install() catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try printer.append(" >> already installed!\n", .{}, .{ .verbosity = 0, .color = 32 });
                    continue;
                },
                else => {
                    try printer.append("  ! [ERROR] Failed to install - {s}...\n", .{package_id}, .{ .verbosity = 0 });
                },
            }
        };
        try printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = 32 });
    }
    try printer.append("\nInstalled all!\n", .{}, .{ .verbosity = 0, .color = 32 });
}
