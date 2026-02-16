const std = @import("std");

pub const Installer = @This();

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");
const Package = @import("package");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;
const Injector = @import("core").Injector;
const Hash = @import("core").Hash;

const Builder = @import("../functions/builder.zig");
const Downloader = @import("lib/download.zig");
const Uninstaller = @import("uninstall.zig");

const Context = @import("context");
const Zon = @import("zon");

ctx: *Context,
downloader: Downloader,

pub fn init(ctx: *Context) Installer {
    const downloader = Downloader.init(ctx);

    return Installer{
        .downloader = downloader,
        .ctx = ctx,
    };
}

pub fn deinit(self: *Installer) void {
    self.downloader.deinit();
}

fn isFetched(
    self: *Installer,
    package_id: []const u8,
) bool {
    const target_path = std.fs.path.join(
        self.ctx.allocator,
        &.{
            self.ctx.paths.pkg_root,
            package_id,
        },
    ) catch return false;
    defer self.ctx.allocator.free(target_path);
    return Fs.existsDir(target_path);
}

fn isLocked(
    self: *Installer,
    name: []const u8,
) bool {
    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return false;
    defer lock.deinit();

    var match = false;
    for (lock.value.packages) |pkg| {
        if (!std.mem.startsWith(u8, pkg.name, name)) continue;
        match = true;
    }
    return match;
}

fn isLinked(
    self: *Installer,
    name: []const u8,
) bool {
    const target_path = std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Default.package_files.zep_folder,
            name,
        },
    ) catch return false;
    defer self.ctx.allocator.free(target_path);

    _ = std.fs.cwd().access(target_path, .{}) catch {
        return false;
    };
    return true;
}

fn isInstalled(
    self: *Installer,
    id: []const u8,
) !bool {
    self.ctx.logger.info("Checking if package is installed", @src());

    var split = std.mem.splitScalar(u8, id, '@');
    const name = split.first();
    const z = self.isLinked(name);
    const l = self.isLocked(id);
    const f = self.isFetched(id);

    return z and l and f;
}

fn isCorrupt(
    self: *Installer,
    package_id: []const u8,
) !bool {
    var split = std.mem.splitScalar(u8, package_id, '@');
    const name = split.first();
    const z = self.isLinked(name);
    if (!z) return false;

    const package_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Default.package_files.zep_folder,
            name,
        },
    );
    defer self.ctx.allocator.free(package_path);

    var symlinked_buffer: [256]u8 = undefined;
    const symlinked = std.fs.cwd().readLink(package_path, &symlinked_buffer) catch
        return true;
    if (!Fs.existsDir(symlinked)) return true;

    return false;
}

fn fixCorrupt(
    self: *Installer,
    id: []const u8,
) !void {
    var split = std.mem.splitScalar(u8, id, '@');
    const name = split.first();

    const package_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Default.package_files.zep_folder,
            name,
        },
    );
    defer self.ctx.allocator.free(package_path);
    Fs.deleteSymlinkIfExists(package_path);
}

fn linkPackage(
    self: *Installer,
    package: *Package,
    force_inject: bool,
) !void {
    self.ctx.logger.info("Linking Package...", @src());

    var injector = Injector.init(
        self.ctx.allocator,
        self.ctx.manifest,
        &self.ctx.printer,
    );

    injector.initInjector(force_inject) catch return Errors.Installable.DownloadFailed;

    // symbolic link
    const target_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            self.ctx.paths.pkg_root,
            package.package_id,
        },
    );
    defer self.ctx.allocator.free(target_path);

    const relative_symbolic_link_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            Constants.Default.package_files.zep_folder,
            package.package.name,
        },
    );
    defer self.ctx.allocator.free(relative_symbolic_link_path);
    Fs.deleteSymlinkIfExists(relative_symbolic_link_path);

    const cwd = try std.fs.cwd().realpathAlloc(self.ctx.allocator, ".");
    defer self.ctx.allocator.free(cwd);

    const absolute_symbolic_link_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            cwd,
            relative_symbolic_link_path,
        },
    );
    defer self.ctx.allocator.free(absolute_symbolic_link_path);
    try std.fs.cwd().symLink(target_path, relative_symbolic_link_path, .{ .is_directory = true });

    package.lockRegister() catch return Errors.Installable.LockFailed;
}

fn resolvePackage(
    self: *Installer,
    name: []const u8,
    version: ?[]const u8,
    namespace: Structs.Extras.Namespaces,
) !Package {
    const v = version orelse "";
    blk: {
        if (v.len == 0) break :blk;
        const package_id = try std.fmt.allocPrint(self.ctx.allocator, "{s}@{s}", .{ name, v });
        defer self.ctx.allocator.free(package_id);
        if (try self.isInstalled(package_id)) return Errors.Installable.AlreadyInstalled;
        if (try self.isCorrupt(package_id)) {
            try self.fixCorrupt(package_id);
        }
        break :blk;
    }

    self.ctx.logger.infof("Getting Package...", .{}, @src());
    const package = try Package.init(
        self.ctx,
        name,
        version,
        namespace,
    );

    self.ctx.logger.infof("Package received!", .{}, @src());

    if (v.len == 0) {
        if (try self.isInstalled(package.package.name)) return Errors.Installable.AlreadyInstalled;
        if (try self.isCorrupt(package.package.name)) {
            try self.fixCorrupt(package.package.name);
        }
    }

    return package;
}

pub fn installBinary(
    self: *Installer,
    name: []const u8,
    version: ?[]const u8,
    namespace: Structs.Extras.Namespaces,
) Errors.Installable!void {
    var binary = try self.resolvePackage(
        name,
        version,
        namespace,
    );
    defer binary.deinit();

    self.ctx.logger.info("Installing Binary...", @src());
    self.ctx.printer.append(
        "Installing Binary {s}\n",
        .{binary.package.name},
        .{
            .verbosity = 3,
        },
    );

    self.ctx.logger.info("Installing Binary via Downloader", @src());
    try self.downloader.downloadBinary(
        binary.package_id,
        binary.package.source,
    );
    self.ctx.logger.info("Installed.", @src());

    try binary.resolveZigVersion(); // resolve the zig version after fetching the source
    const binary_path = try std.fs.path.join(self.ctx.allocator, &.{
        self.ctx.paths.pkg_root,
        binary.package_id,
    });
    defer self.ctx.allocator.free(binary_path);
    const zig_version = if (std.mem.eql(u8, binary.package.zig_version, "/")) Constants.Default.zig_version else binary.package.zig_version;
    self.ctx.printer.append(
        "Building binary;\n > Path: {s}\n > Zig: {s}\n\n",
        .{ binary_path, zig_version },
        .{
            .verbosity = 3,
        },
    );

    Locales.PRINTER_MUTE = true;
    errdefer Locales.PRINTER_MUTE = false;
    const target_files = Builder.build(
        self.ctx,
        binary_path,
        zig_version,
        .{
            .mute = true,
        },
    ) catch return Errors.Installable.InstallFailed;
    defer self.ctx.allocator.free(target_files);
    Locales.PRINTER_MUTE = false;

    self.ctx.printer.append(
        "Successfully installed - {s}\n",
        .{binary.package.name},
        .{ .color = .green },
    );
    self.ctx.printer.append(
        "You might need to restart your terminal.\n\n",
        .{},
        .{ .color = .bright_black },
    );
}

pub fn installPackage(
    self: *Installer,
    name: []const u8,
    version: ?[]const u8,
    namespace: Structs.Extras.Namespaces,
    force_inject: bool,
) Errors.Installable!void {
    var package = self.resolvePackage(
        name,
        version,
        namespace,
    ) catch |err| {
        switch (err) {
            Errors.Installable.AlreadyInstalled => return Errors.Installable.AlreadyInstalled,
            else => return Errors.Installable.ResolveFailed,
        }
    };
    defer package.deinit();

    self.ctx.logger.info(
        "Installing Package...",
        @src(),
    );
    self.ctx.printer.append(
        "Installing Package {s}\n",
        .{package.package.name},
        .{
            .verbosity = 3,
        },
    );

    blk: {
        if (self.isLocked(package.package.name)) break :blk;
        var uninstaller = Uninstaller.init(self.ctx);
        defer uninstaller.deinit();
        Locales.PRINTER_MUTE = true;
        uninstaller.uninstallPackage(package.package.name) catch |err| {
            Locales.PRINTER_MUTE = false;
            switch (err) {
                error.NotInstalled => break :blk,
                else => return err,
            }
        };
        Locales.PRINTER_MUTE = false;
        break :blk;
    }

    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Installable.ManifestFailed;
    defer lock.deinit();

    self.downloader.downloadPackage(
        package.package_id,
        package.package.source,
    ) catch return Errors.Installable.DownloadFailed;
    self.ctx.logger.info(
        "Installed.",
        @src(),
    );

    try package.resolveZigVersion();
    if (!std.mem.containsAtLeast(
        u8,
        package.package.zig_version,
        1,
        lock.value.root.zig_version,
    )) {
        self.ctx.printer.append(
            "WARNING: ",
            .{},
            .{
                .color = .red,
                .weight = .bold,
                .verbosity = 2,
            },
        );
        self.ctx.printer.append(
            "ZIG VERSIONS ARE NOT MATCHING!\n",
            .{},
            .{
                .color = .blue,
                .weight = .bold,
                .verbosity = 2,
            },
        );
        self.ctx.printer.append(
            "{s} Zig Version: {s}\nYour Zig Version: {s}\n\n",
            .{ package.package.name, package.package.zig_version, lock.value.root.zig_version },
            .{ .verbosity = 2 },
        );
    }

    self.linkPackage(&package, force_inject) catch |err| {
        switch (err) {
            Errors.Installable.InjectFailed => return Errors.Installable.InjectFailed,
            Errors.Installable.LockFailed => return Errors.Installable.LockFailed,
            else => return Errors.Installable.LinkingFailed,
        }
    };
    self.ctx.printer.append(
        "Successfully installed - {s}\n\n",
        .{package.package.name},
        .{ .color = .green },
    );
}

pub fn installAll(self: *Installer) Errors.Installable!void {
    self.ctx.logger.info(
        "Installing All",
        @src(),
    );

    var lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Installable.LockFailed;
    defer lock.deinit();

    var failed: u8 = 0;
    for (lock.value.packages) |package| {
        const install = package.install;
        var split = std.mem.splitAny(u8, install, "@");
        const name = split.first();
        const version = split.next();

        self.ctx.printer.append(
            " > Installing - {s}",
            .{install},
            .{ .verbosity = 0 },
        );

        self.installPackage(
            name,
            version,
            package.namespace,
            false,
        ) catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    self.ctx.printer.append(
                        " >> already installed!\n",
                        .{},
                        .{ .verbosity = 0, .color = .green },
                    );
                    continue;
                },
                else => {
                    failed += 1;
                    self.ctx.printer.append(
                        "  ! [ERROR] Failed to install - {s} [{any}]...\n",
                        .{ name, err },
                        .{ .verbosity = 0, .color = .red },
                    );
                },
            }
            continue;
        };

        self.ctx.printer.append(
            " >> done!\n",
            .{},
            .{ .verbosity = 0, .color = .green },
        );
    }

    self.ctx.printer.append(
        "\nInstalled: {d} packages ({d} failed)\n",
        .{
            lock.value.packages.len - failed,
            failed,
        },
        .{ .verbosity = 0 },
    );
}
