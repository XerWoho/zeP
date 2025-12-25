const std = @import("std");

pub const Package = @This();

const Logger = @import("logger");
const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("manifest.zig");
const Hash = @import("hash.zig");
const Json = @import("json.zig");
const Fetch = @import("fetch.zig");

fn resolveVersion(
    package_name: []const u8,
    package_version: ?[]const u8,
    fetcher: *Fetch,
    printer: *Printer,
) !Structs.Packages.PackageVersions {
    try printer.append("Finding the package...\n", .{}, .{});

    const parsed_package = try fetcher.fetchPackage(package_name);
    defer parsed_package.deinit();

    try printer.append("Package Found! - {s}\n\n", .{package_name}, .{ .color = .green });

    const versions = parsed_package.value.versions;
    if (versions.len == 0) {
        printer.append("\nPackage has no version!\n", .{}, .{ .color = .red }) catch {};
        return error.PackageVersion;
    }

    try printer.append("Getting the package version...\n", .{}, .{});
    try printer.append("Target Version: {s}\n\n", .{package_version orelse "/ (using latest)"}, .{});
    const target_version = package_version orelse versions[0].version;
    var check_selected: ?Structs.Packages.PackageVersions = null;
    for (versions) |v| {
        if (std.mem.eql(u8, v.version, target_version)) {
            check_selected = v;
            break;
        }
    }

    const version = check_selected orelse return error.NotFound;

    try printer.append("Package version found!\n\n", .{}, .{ .color = .green });
    return version;
}

/// Handles Packages, returns null if package is not found.
/// Rolls back to latest version if none was specified.
/// Hashes are generated on init.
allocator: std.mem.Allocator,
printer: *Printer,

package_hash: []const u8,
package_name: []const u8,
package_version: []const u8,
package: Structs.Packages.PackageVersions,

id: []u8, // <-- package_name@package_version

pub fn init(
    allocator: std.mem.Allocator,
    printer: *Printer,
    fetcher: *Fetch,
    package_name: []const u8,
    package_version: ?[]const u8,
) !Package {
    const logger = Logger.get();
    try logger.infof("Package.init: finding package {s}", .{package_name}, @src());
    const version = try resolveVersion(
        package_name,
        package_version,
        fetcher,
        printer,
    );

    // Create hash
    try logger.infof("Package.init: computed hash for {s}@{s}", .{ package_name, version.version }, @src());

    const id = try std.fmt.allocPrint(allocator, "{s}@{s}", .{
        package_name,
        version.version,
    });

    const hash = try Hash.hashData(allocator, version.url);

    return Package{
        .allocator = allocator,
        .package_name = package_name,
        .package_hash = hash,
        .package_version = version.version,
        .package = version,
        .printer = printer,
        .id = id,
    };
}

pub fn deinit(self: *Package) void {
    const logger = Logger.get();
    logger.infof("Package.deinit: freeing package {s}", .{self.id}, @src()) catch {};
    self.allocator.free(self.id);
}

fn getPackagePathsAmount(
    self: *Package,
    paths: Constants.Paths.Paths,
    manifest: *Manifest,
) !usize {
    const logger = Logger.get();
    try logger.infof("getPackagePathsAmount: checking package {s}", .{self.id}, @src());

    var package_manifest = try manifest.readManifest(
        Structs.Manifests.PackagesManifest,
        paths.pkg_manifest,
    );
    defer package_manifest.deinit();

    var package_paths_amount: usize = 0;
    for (package_manifest.value.packages) |package| {
        if (std.mem.eql(u8, package.name, self.id)) {
            package_paths_amount = package.paths.len;
            break;
        }
    }

    try logger.infof("getPackagePathsAmount: package {s} has {d} paths", .{ self.id, package_paths_amount }, @src());
    return package_paths_amount;
}

pub fn deletePackage(
    self: *Package,
    paths: Constants.Paths.Paths,
    manifest: *Manifest,
    force: bool,
) !void {
    const logger = Logger.get();
    try logger.infof("deletePackage: attempting to delete {s}", .{self.id}, @src());

    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &buf,
        "{s}/{s}",
        .{ paths.pkg_root, self.id },
    );
    if (!Fs.existsDir(path)) return error.NotInstalled;

    const amount = try self.getPackagePathsAmount(paths, manifest);
    if (amount > 0 and !force) {
        try logger.warnf("deletePackage: package {s} is used by {d} projects, aborting deletion", .{ self.id, amount }, @src());
        return error.InUse;
    }

    if (Fs.existsDir(path)) {
        try Fs.deleteTreeIfExists(path);
        try logger.infof("deletePackage: deleted package directory {s}", .{path}, @src());
    }
}
