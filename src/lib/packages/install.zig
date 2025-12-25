const std = @import("std");

pub const Installer = @This();

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Package = @import("core").Package;
const Injector = @import("core").Injector;
const Hash = @import("core").Hash;

const Downloader = @import("lib/download.zig");
const Uninstaller = @import("uninstall.zig");

const Context = @import("context");

ctx: *Context,
downloader: Downloader,
force_inject: bool = false,
install_unverified_packages: bool = false,

pub fn init(
    ctx: *Context,
) Installer {
    const downloader = Downloader.init(ctx);

    return Installer{
        .downloader = downloader,
        .ctx = ctx,
    };
}

pub fn deinit(self: *Installer) void {
    self.downloader.deinit();
}

fn checkIfPackageInstalled(
    self: *Installer,
    package_id: []const u8,
) !bool {
    const target_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            self.ctx.paths.pkg_root,
            package_id,
        },
    );
    defer self.ctx.allocator.free(target_path);
    return Fs.existsDir(target_path);
}

fn uninstallPrevious(
    self: *Installer,
    package: Package,
) !void {
    const lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );
    defer lock.deinit();
    for (lock.value.packages) |lock_package| {
        var uninstaller = Uninstaller.init(self.ctx);
        defer uninstaller.deinit();
        if (std.mem.eql(u8, lock_package.name, package.id)) {
            try self.setPackage(package);

            try self.ctx.printer.append(
                "UNINSTALLING PREVIOUS [{s}]\n",
                .{try self.ctx.allocator.dupe(u8, lock_package.name)},
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
    if (package_version) |v| {
        const package_id = try std.fmt.allocPrint(self.ctx.allocator, "{s}@{s}", .{ package_name, v });
        if (try self.checkIfPackageInstalled(package_id)) return error.AlreadyInstalled;
    }

    self.ctx.fetcher.install_unverified_packages = self.install_unverified_packages;
    var package = try Package.init(
        self.ctx.allocator,
        &self.ctx.printer,
        &self.ctx.fetcher,
        package_name,
        package_version,
    );
    defer package.deinit();

    const parsed = package.package;
    try self.uninstallPrevious(package);

    const lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );

    defer lock.deinit();
    if (!std.mem.containsAtLeast(u8, parsed.zig_version, 1, lock.value.root.zig_version)) {
        try self.ctx.printer.append("WARNING: ", .{}, .{
            .color = .red,
            .weight = .bold,
        });
        try self.ctx.printer.append("ZIG VERSIONS ARE NOT MATCHING!\n", .{}, .{
            .color = .blue,
            .weight = .bold,
        });
        try self.ctx.printer.append("{s} Zig Version: {s}\n", .{ package.id, parsed.zig_version }, .{});
        try self.ctx.printer.append("Your Zig Version: {s}\n\n", .{lock.value.root.zig_version}, .{});
    }

    try self.ctx.printer.append("Checking Hash...\n", .{}, .{});
    if (std.mem.eql(u8, package.package_hash, parsed.sha256sum)) {
        try self.ctx.printer.append("  > HASH IDENTICAL\n", .{}, .{ .color = .green });
    } else {
        return error.HashMismatch;
    }

    try self.downloader.downloadPackage(
        package.id,
        parsed.url,
        self.install_unverified_packages,
    );

    try self.setPackage(package);
    try self.ctx.printer.append("Successfully installed - {s}\n\n", .{package.package_name}, .{ .color = .green });
}

fn setPackage(
    self: *Installer,
    package: Package,
) !void {
    try self.addPackageToJson(package);

    var injector = try Injector.init(
        self.ctx.allocator,
        &self.ctx.printer,
        &self.ctx.manifest,
        self.force_inject,
    );
    try injector.initInjector();

    // symbolic link
    var buf: [256]u8 = undefined;
    const target_path = try std.fmt.bufPrint(
        &buf,
        "{s}/{s}",
        .{
            self.ctx.paths.pkg_root,
            package.id,
        },
    );

    const relative_symbolic_link_path = try std.fs.path.join(self.ctx.allocator, &.{ Constants.Extras.package_files.zep_folder, package.package_name });
    Fs.deleteTreeIfExists(relative_symbolic_link_path) catch {};
    Fs.deleteFileIfExists(relative_symbolic_link_path) catch {};
    defer self.ctx.allocator.free(relative_symbolic_link_path);

    const cwd = try std.fs.cwd().realpathAlloc(self.ctx.allocator, ".");
    defer self.ctx.allocator.free(cwd);

    const absolute_symbolic_link_path = try std.fs.path.join(self.ctx.allocator, &.{ cwd, relative_symbolic_link_path });
    defer self.ctx.allocator.free(absolute_symbolic_link_path);
    try std.fs.cwd().symLink(target_path, relative_symbolic_link_path, .{ .is_directory = true });
    self.ctx.manifest.addPathToManifest(
        package.id,
        absolute_symbolic_link_path,
    ) catch {
        return error.AddingToManifestFailed;
        // try self.ctx.printer.append("Adding to manifest failed!\n", .{}, .{ .color = .red });
    };
}

fn addPackageToJson(
    self: *Installer,
    package: Package,
) !void {
    var package_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    var lock_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );

    defer package_json.deinit();
    defer lock_json.deinit();
    try self.ctx.manifest.manifestAdd(
        &package_json.value,
        package.package_name,
        package.id,
    );
    try self.ctx.manifest.lockAdd(
        &lock_json.value,
        package,
    );
}

pub fn installAll(self: *Installer) anyerror!void {
    var package_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );

    defer package_json.deinit();
    for (package_json.value.packages) |package_id| {
        try self.ctx.printer.append(" > Installing - {s}...\n", .{package_id}, .{ .verbosity = 0 });

        var package_split = std.mem.splitScalar(u8, package_id, '@');
        const package_name = package_split.first();
        const package_version = package_split.next();
        self.install(package_name, package_version) catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    try self.ctx.printer.append(" >> already installed!\n", .{}, .{ .verbosity = 0, .color = .green });
                    continue;
                },
                else => {
                    try self.ctx.printer.append("  ! [ERROR] Failed to install - {s}...\n", .{package_id}, .{ .verbosity = 0 });
                },
            }
        };
        try self.ctx.printer.append(" >> done!\n", .{}, .{ .verbosity = 0, .color = .green });
    }
    try self.ctx.printer.append("\nInstalled all!\n", .{}, .{ .verbosity = 0, .color = .green });
}
