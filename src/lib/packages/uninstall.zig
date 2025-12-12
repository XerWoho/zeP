const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Injector = @import("core").Injector.Injector;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json.Json;

/// Handles the uninstallation of a package
pub const Uninstaller = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
    json: *Json,
    package_name: []const u8,
    package_version: []const u8,
    package_id: []const u8,

    /// Initialize the uninstaller with allocator, package name, and printer
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        json: *Json,
        paths: *Constants.Paths.Paths,
        package_name: []const u8,
    ) !Uninstaller {
        const lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock);
        var package_version: []const u8 = "";
        for (lock.value.packages) |package| {
            if (std.mem.startsWith(u8, package.name, package_name)) {
                var split = std.mem.splitScalar(u8, package.name, '@');
                _ = split.first();
                const version = split.next();
                if (version) |v| {
                    package_version = v;
                } else {
                    return error.NotInstalled;
                }

                break;
            }
            continue;
        }

        if (package_version.len == 0) {
            return error.NotInstalled;
        }
        return Uninstaller{
            .allocator = allocator,
            .package_name = package_name,
            .package_version = package_version,
            .package_id = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ package_name, package_version }),
            .json = json,
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(self: *Uninstaller) void {
        self.allocator.free(self.package_id);
    }

    /// Main uninstallation routine
    pub fn uninstall(self: *Uninstaller) !void {
        try self.printer.append("Deleting Package...\n[{s}]\n\n", .{self.package_name}, .{});
        try self.removePackageFromJson();

        var injector = Injector.init(self.allocator, self.package_name, self.printer);
        try injector.initInjector();

        // Remove symbolic link
        const symbolic_link_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ Constants.Extras.package_files.zep_folder, self.package_name });
        defer self.allocator.free(symbolic_link_path);
        if (Fs.existsDir(symbolic_link_path)) {
            Fs.deleteTreeIfExists(symbolic_link_path) catch {};
            Fs.deleteFileIfExists(symbolic_link_path) catch {};

            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);

            const absolute_path = try std.fs.path.join(self.allocator, &.{ cwd, symbolic_link_path });
            defer self.allocator.free(absolute_path);

            // ! Handles the deletion of the package
            // ! as the package can ONLY be deleted,
            // ! if no other project uses it
            // !
            try Manifest.removePathFromManifest(
                self.json,
                self.package_name,
                self.package_id,
                absolute_path,
                self.paths,
            );
        }
        try self.removePackageFromJson();
        try self.printer.append("Successfully deleted - {s}\n\n", .{self.package_name}, .{ .color = .green });
    }

    /// Remove package from `zep.json` and `zep.lock`
    pub fn removePackageFromJson(self: *Uninstaller) !void {
        var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        var lock_json = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);

        defer package_json.deinit();
        defer lock_json.deinit();

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        try manifestRemove(&package_json.value, self.package_name, self.json);
        try lockRemove(&lock_json.value, self.package_name, self.json);
        Locales.VERBOSITY_MODE = previous_verbosity;
    }
};

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

fn lockRemove(
    lock: *Structs.ZepFiles.PackageLockStruct,
    package_name: []const u8,
    json: *Json,
) !void {
    const allocator = std.heap.page_allocator;

    lock.packages = try filterOut(
        allocator,
        lock.packages,
        package_name,
        Structs.ZepFiles.LockPackageStruct,
        struct {
            fn match(item: Structs.ZepFiles.LockPackageStruct, ctx: []const u8) bool {
                return std.mem.startsWith(u8, item.name, ctx);
            }
        }.match,
    );

    var package_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);
    defer package_json.deinit();
    lock.root = package_json.value;

    try json.writePretty(Constants.Extras.package_files.lock, lock);
}

fn manifestRemove(
    pkg: *Structs.ZepFiles.PackageJsonStruct,
    package_name: []const u8,
    json: *Json,
) !void {
    const allocator = std.heap.page_allocator;

    pkg.packages = try filterOut(
        allocator,
        pkg.packages,
        package_name,
        []const u8,
        struct {
            fn match(item: []const u8, ctx: []const u8) bool {
                return std.mem.startsWith(u8, item, ctx);
            }
        }.match,
    );

    try json.writePretty(Constants.Extras.package_files.manifest, pkg);
}
