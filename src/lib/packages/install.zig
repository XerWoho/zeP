const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("core").Json;
const Compressor = @import("core").Compressor;
const Package = @import("core").Package;
const Injector = @import("core").Injector;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

const Cacher = @import("lib/cache.zig").Cacher;
const Downloader = @import("lib/download.zig").Downloader;
const Uninstaller = @import("uninstall.zig").Uninstaller;

pub const Installer = struct {
    allocator: std.mem.Allocator,
    json: *Json,
    downloader: Downloader,
    cacher: Cacher,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
    manifest: *Manifest,
    force_inject: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        json: *Json,
        paths: *Constants.Paths.Paths,
        manifest: *Manifest,
        force_inject: bool,
    ) !Installer {
        const cacher = try Cacher.init(
            allocator,
            printer,
            paths,
        );
        const downloader = try Downloader.init(
            allocator,
            cacher,
            printer,
            paths,
        );

        return Installer{
            .json = json,
            .allocator = allocator,
            .downloader = downloader,
            .cacher = cacher,
            .printer = printer,
            .paths = paths,
            .manifest = manifest,
            .force_inject = force_inject,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cacher.deinit();
        self.downloader.deinit();
    }

    fn checkIfPackageInstalled(
        self: *Installer,
        package_id: []const u8,
    ) !bool {
        const target_path = try std.fs.path.join(
            self.allocator,
            &.{
                self.paths.pkg_root,
                package_id,
            },
        );
        defer self.allocator.free(target_path);
        return Fs.existsDir(target_path);
    }

    fn uninstallPrevious(
        self: *Installer,
        package: Package,
    ) !void {
        const lock = try self.manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );
        defer lock.deinit();
        for (lock.value.packages) |lockPackage| {
            var uninstaller = try Uninstaller.init(
                self.allocator,
                self.printer,
                self.json,
                self.paths,
                self.manifest,
            );
            defer uninstaller.deinit();
            if (std.mem.eql(u8, lockPackage.name, package.id)) {
                if (try self.checkIfPackageInstalled(package.id)) return error.AlreadyInstalled;
                try self.setPackage(package);

                try self.printer.append(
                    "UNINSTALLING PREVIOUS [{s}]\n",
                    .{try self.allocator.dupe(u8, lockPackage.name)},
                    .{ .color = .red },
                );
                const previous_verbosity = Locales.VERBOSITY_MODE;
                Locales.VERBOSITY_MODE = 0;

                var split = std.mem.splitScalar(u8, package.id, '@');
                const package_name = split.first();
                try uninstaller.uninstall(package_name);

                Locales.VERBOSITY_MODE = previous_verbosity;
            }
        }
    }

    pub fn install(
        self: *Installer,
        package_name: []const u8,
        package_version: ?[]const u8,
    ) !void {
        var package = try Package.init(
            self.allocator,
            self.printer,
            self.json,
            self.paths,
            self.manifest,
            package_name,
            package_version,
        );
        const parsed = package.package;
        try self.uninstallPrevious(package);

        const lock = try self.manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );

        defer lock.deinit();
        if (!std.mem.containsAtLeast(u8, parsed.zig_version, 1, lock.value.root.zig_version)) {
            try self.printer.append("WARNING: ", .{}, .{
                .color = .red,
                .weight = .bold,
            });
            try self.printer.append("ZIG VERSIONS ARE NOT MATCHING!\n", .{}, .{
                .color = .blue,
                .weight = .bold,
            });
            try self.printer.append("{s} Zig Version: {s}\n", .{ package.id, parsed.zig_version }, .{});
            try self.printer.append("Your Zig Version: {s}\n\n", .{lock.value.root.zig_version}, .{});
        }

        try self.printer.append("Downloading Package...\n", .{}, .{});
        try self.downloader.downloadPackage(package.id, parsed.url);

        try self.printer.append("\nChecking hash...\n", .{}, .{});
        if (std.mem.eql(u8, package.package_hash, parsed.sha256sum)) {
            try self.printer.append("  > HASH IDENTICAL\n", .{}, .{ .color = .green });
        } else {
            try package.deletePackage(true); // force
            try self.cacher.deletePackageFromCache(package.id);
            return error.HashMismatch;
        }

        try self.printer.append("\nChecking Cache...\n", .{}, .{});
        const is_package_cached = try self.cacher.isPackageCached(package.id);
        if (!is_package_cached) {
            try self.printer.append("Not Cached! Caching...\n", .{}, .{});
            const is_cached = try self.cacher.setPackageToCache(package.id);
            if (is_cached) {
                try self.printer.append(" > PACKAGE CACHED!\n\n", .{}, .{
                    .color = .green,
                });
            } else {
                try self.printer.append(" ! CACHING FAILED!\n\n", .{}, .{
                    .color = .red,
                });
            }
        } else {
            try self.printer.append("PACKAGE ALREADY CACHED! SKIPPING CACHING!\n\n", .{}, .{});
        }

        try self.setPackage(package);
        try self.printer.append("Successfully installed - {s}\n\n", .{package.package_name}, .{ .color = .green });
    }

    fn setPackage(
        self: *Installer,
        package: Package,
    ) !void {
        try self.addPackageToJson(package);

        var injector = try Injector.init(
            self.allocator,
            self.printer,
            self.manifest,
            self.force_inject,
        );
        try injector.initInjector();

        // symbolic link
        var buf: [256]u8 = undefined;
        const target_path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}",
            .{
                self.paths.pkg_root,
                package.id,
            },
        );

        const relative_symbolic_link_path = try std.fs.path.join(self.allocator, &.{ Constants.Extras.package_files.zep_folder, package.package_name });
        Fs.deleteTreeIfExists(relative_symbolic_link_path) catch {};
        Fs.deleteFileIfExists(relative_symbolic_link_path) catch {};
        defer self.allocator.free(relative_symbolic_link_path);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const absolute_symbolic_link_path = try std.fs.path.join(self.allocator, &.{ cwd, relative_symbolic_link_path });
        defer self.allocator.free(absolute_symbolic_link_path);
        try std.fs.cwd().symLink(target_path, relative_symbolic_link_path, .{ .is_directory = true });
        self.manifest.addPathToManifest(
            package.id,
            absolute_symbolic_link_path,
        ) catch {
            try self.printer.append("Adding to manifest failed!\n", .{}, .{ .color = .red });
        };
    }

    fn addPackageToJson(
        self: *Installer,
        package: Package,
    ) !void {
        var package_json = try self.manifest.readManifest(
            Structs.ZepFiles.PackageJsonStruct,
            Constants.Extras.package_files.manifest,
        );
        var lock_json = try self.manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );

        defer package_json.deinit();
        defer lock_json.deinit();
        try manifestAdd(
            &package_json.value,
            package.package_name,
            package.id,
            self.json,
        );
        try lockAdd(
            &lock_json.value,
            package,
            self.json,
            self.manifest,
        );
    }

    pub fn installAll(self: *Installer) anyerror!void {
        var package_json = try self.manifest.readManifest(
            Structs.ZepFiles.PackageJsonStruct,
            Constants.Extras.package_files.manifest,
        );

        defer package_json.deinit();
        for (package_json.value.packages) |package_id| {
            try self.printer.append(" > Installing - {s}...\n", .{package_id}, .{ .verbosity = 0 });

            var package_split = std.mem.splitScalar(u8, package_id, '@');
            const package_name = package_split.first();
            const package_version = package_split.next();
            self.install(package_name, package_version) catch |err| {
                switch (err) {
                    error.AlreadyInstalled => {
                        try self.printer.append(" >> already installed!\n", .{}, .{ .verbosity = 0, .color = .green });
                        continue;
                    },
                    else => {
                        try self.printer.append("  ! [ERROR] Failed to install - {s}...\n", .{package_id}, .{ .verbosity = 0 });
                    },
                }
            };
            try self.printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });
        }
        try self.printer.append("\nInstalled all!\n", .{}, .{ .verbosity = 0, .color = .green });
    }
};

fn appendUnique(
    comptime T: type,
    list: []const T,
    new_item: T,
    allocator: std.mem.Allocator,
    matchFn: fn (a: T, b: T) bool,
) ![]T {
    var arr = try std.ArrayList(T).initCapacity(allocator, 10);
    defer arr.deinit(allocator);

    for (list) |item| {
        try arr.append(allocator, item);
        if (matchFn(item, new_item))
            return arr.toOwnedSlice(allocator);
    }

    try arr.append(allocator, new_item);
    return arr.toOwnedSlice(allocator);
}

fn filterOut(
    allocator: std.mem.Allocator,
    list: anytype,
    filter: []const u8,
    comptime T: type,
    matchFn: fn (a: T, b: []const u8) bool,
) ![]T {
    var out = try std.ArrayList(T).initCapacity(allocator, 10);
    defer out.deinit(allocator);

    for (list) |item| {
        if (!matchFn(item, filter))
            try out.append(allocator, item);
    }

    return out.toOwnedSlice(allocator);
}

fn manifestAdd(
    pkg: *Structs.ZepFiles.PackageJsonStruct,
    package_name: []const u8,
    package_id: []const u8,
    json: *Json,
) !void {
    const alloc = std.heap.page_allocator;

    pkg.packages = try filterOut(
        alloc,
        pkg.packages,
        package_name,
        []const u8,
        struct {
            fn match(a: []const u8, b: []const u8) bool {
                return std.mem.startsWith(u8, a, b); // first remove the previous package Name
            }
        }.match,
    );

    pkg.packages = try appendUnique(
        []const u8,
        pkg.packages,
        package_id,
        alloc,
        struct {
            fn match(a: []const u8, b: []const u8) bool {
                return std.mem.startsWith(u8, a, b);
            }
        }.match,
    );

    try json.writePretty(Constants.Extras.package_files.manifest, pkg);
}

fn lockAdd(
    lock: *Structs.ZepFiles.PackageLockStruct,
    package: Package,
    json: *Json,
    manifest: *Manifest,
) !void {
    const new_entry = Structs.ZepFiles.LockPackageStruct{
        .name = package.id,
        .hash = package.package_hash,
        .source = package.package.url,
        .zig_version = package.package.zig_version,
        .root_file = package.package.root_file,
    };

    const alloc = std.heap.page_allocator;
    lock.packages = try filterOut(
        alloc,
        lock.packages,
        package.package_name,
        Structs.ZepFiles.LockPackageStruct,
        struct {
            fn match(item: Structs.ZepFiles.LockPackageStruct, ctx: []const u8) bool {
                return std.mem.startsWith(u8, item.name, ctx);
            }
        }.match,
    );

    lock.packages = try appendUnique(
        Structs.ZepFiles.LockPackageStruct,
        lock.packages,
        new_entry,
        alloc,
        struct {
            fn match(item: Structs.ZepFiles.LockPackageStruct, ctx: Structs.ZepFiles.LockPackageStruct) bool {
                return std.mem.startsWith(u8, item.name, ctx.name);
            }
        }.match,
    );

    var package_json = try manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer package_json.deinit();
    lock.root = package_json.value;

    try json.writePretty(Constants.Extras.package_files.lock, lock);
}
