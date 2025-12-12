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
    json: *Json,
    package: Package,
    downloader: Downloader,
    cacher: Cacher,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        json: *Json,
        paths: *Constants.Paths.Paths,
        opt_package_name: ?[]const u8,
        opt_package_version_target: ?[]const u8,
    ) !Installer {
        const package_name = opt_package_name orelse {
            const previous_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;

            try printer.append("Installing all packages...\n", .{}, .{ .verbosity = 0 });

            try installAll(
                allocator,
                printer,
                paths,
                json,
            );

            Locales.VERBOSITY_MODE = previous_verbosity;
            return error.NoPackageSpecified;
        };

        const package = try Package.init(
            allocator,
            printer,
            json,
            paths,
            package_name,
            opt_package_version_target,
        );
        const cacher = try Cacher.init(
            allocator,
            package,
            printer,
            paths,
        );
        const downloader = try Downloader.init(
            allocator,
            package,
            cacher,
            printer,
            paths,
        );

        return Installer{
            .json = json,
            .allocator = allocator,
            .package = package,
            .downloader = downloader,
            .cacher = cacher,
            .printer = printer,
            .paths = paths,
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

        for (lock.value.packages) |lockPackage| {
            if (std.mem.startsWith(u8, lockPackage.name, self.package.package_name)) {
                if (std.mem.eql(u8, lockPackage.name, self.package.id)) {
                    const target_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}@{s}", .{
                        self.paths.pkg_root,
                        self.package.package_name,
                        self.package.package_version,
                    });
                    defer self.allocator.free(target_path);
                    if (!Fs.existsDir(target_path)) break;

                    try self.setPackage();
                    return error.AlreadyInstalled;
                }

                try self.printer.append("MATCHED UNINSTALLING\n", .{}, .{ .color = .red });
                const previous_verbosity = Locales.VERBOSITY_MODE;
                Locales.VERBOSITY_MODE = 0;

                var uninstaller = try Uninstaller.init(
                    self.allocator,
                    self.printer,
                    self.json,
                    self.paths,
                    self.package.package_name,
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
        try self.printer.append("Successfully installed - {s}\n\n", .{package.package_name}, .{ .color = .green });
    }

    fn setPackage(self: *Installer) !void {
        try self.addPackageToJson();
        const package = self.package;

        var injector = Injector.init(self.allocator, package.package_name, self.printer);
        try injector.initInjector();

        // symbolic link
        const target_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}@{s}", .{
            self.paths.pkg_root,
            package.package_name,
            package.package_version,
        });
        defer self.allocator.free(target_path);

        const relative_symbolic_link_path = try std.fs.path.join(self.allocator, &.{ Constants.Extras.package_files.zep_folder, package.package_name });
        Fs.deleteTreeIfExists(relative_symbolic_link_path) catch {};
        Fs.deleteFileIfExists(relative_symbolic_link_path) catch {};
        defer self.allocator.free(relative_symbolic_link_path);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const absolute_symbolic_link_path = try std.fs.path.join(self.allocator, &.{ cwd, relative_symbolic_link_path });
        defer self.allocator.free(absolute_symbolic_link_path);
        try std.fs.cwd().symLink(target_path, relative_symbolic_link_path, .{ .is_directory = true });
        Manifest.addPathToManifest(
            self.json,
            self.package.id,
            absolute_symbolic_link_path,
            self.paths,
        ) catch {
            try self.printer.append("Adding to manifest failed!\n", .{}, .{ .color = .red });
        };
    }

    fn addPackageToJson(self: *Installer) !void {
        var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        var lock_json = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);

        defer package_json.deinit();
        defer lock_json.deinit();
        try manifestAdd(&package_json.value, self.package.package_name, self.package.id, self.json);
        try lockAdd(&lock_json.value, self.package, self.json);
    }
};

fn appendUnique(
    comptime T: type,
    list: []const T,
    new_item: T,
    allocator: std.mem.Allocator,
    matchFn: fn (a: T, b: T) bool,
) ![]T {
    var arr = std.ArrayList(T).init(allocator);
    defer arr.deinit();

    for (list) |item| {
        try arr.append(item);
        if (matchFn(item, new_item))
            return arr.toOwnedSlice();
    }

    try arr.append(new_item);
    return arr.toOwnedSlice();
}

fn filterOut(
    allocator: std.mem.Allocator,
    list: anytype,
    filter: []const u8,
    comptime T: type,
    matchFn: fn (a: T, b: []const u8) bool,
) ![]T {
    var out = std.ArrayList(T).init(allocator);
    defer out.deinit();

    for (list) |item| {
        if (!matchFn(item, filter))
            try out.append(item);
    }

    return out.toOwnedSlice();
}

fn manifestAdd(
    pkg: *Structs.ZepFiles.PackageJsonStruct,
    package_name: []const u8,
    package_id: []const u8,
    json: *Json,
) !void {
    const allocator = std.heap.page_allocator;

    pkg.packages = try filterOut(
        allocator,
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
        allocator,
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
) !void {
    const new_entry = Structs.ZepFiles.LockPackageStruct{
        .name = package.id,
        .hash = package.package_hash,
        .source = package.package.url,
        .zig_version = package.package.zig_version,
        .root_file = package.package.root_file,
    };

    const allocator = std.heap.page_allocator;
    lock.packages = try filterOut(
        allocator,
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
        allocator,
        struct {
            fn match(item: Structs.ZepFiles.LockPackageStruct, ctx: Structs.ZepFiles.LockPackageStruct) bool {
                return std.mem.startsWith(u8, item.name, ctx.name);
            }
        }.match,
    );

    var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);
    defer package_json.deinit();
    lock.root = package_json.value;

    try json.writePretty(Constants.Extras.package_files.lock, lock);
}

fn installAll(
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
    json: *Json,
) anyerror!void {
    var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);

    defer package_json.deinit();
    for (package_json.value.packages) |package_id| {
        try printer.append(" > Installing - {s}...\n", .{package_id}, .{ .verbosity = 0 });

        var package_split = std.mem.splitScalar(u8, package_id, '@');
        const package_name = package_split.first();
        const package_version = package_split.next();
        var installer = try Installer.init(
            allocator,
            printer,
            json,
            paths,
            package_name,
            package_version,
        );
        installer.install() catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try printer.append(" >> already installed!\n", .{}, .{ .verbosity = 0, .color = .green });
                    continue;
                },
                else => {
                    try printer.append("  ! [ERROR] Failed to install - {s}...\n", .{package_id}, .{ .verbosity = 0 });
                },
            }
        };
        try printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });
    }
    try printer.append("\nInstalled all!\n", .{}, .{ .verbosity = 0, .color = .green });
}
