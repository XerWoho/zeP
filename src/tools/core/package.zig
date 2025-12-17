const std = @import("std");

const Logger = @import("logger");
const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Hash = @import("hash.zig");
const Manifest = @import("manifest.zig").Manifest;
const Json = @import("json.zig").Json;

/// Handles Packages, returns null if package is not found.
/// Rolls back to latest version if none was specified.
/// Hashes are generated on init.
pub const Package = struct {
    allocator: std.mem.Allocator,
    json: *Json,
    paths: *Constants.Paths.Paths,
    manifest: *Manifest,

    package_hash: []u8,
    package_name: []const u8,
    package_version: []const u8,
    package: Structs.Packages.PackageVersions,

    id: []u8, // <-- package_name@package_version

    printer: *Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        json: *Json,
        paths: *Constants.Paths.Paths,
        manifest: *Manifest,
        package_name: []const u8,
        package_version: ?[]const u8,
    ) !Package {
        const logger = Logger.get();
        try logger.debugf("Package.init: finding package {s}", .{package_name}, @src());

        try printer.append("Finding the package...\n", .{}, .{});

        // Load package manifest
        const parsed_package = try json.parsePackage(package_name);
        defer parsed_package.deinit();

        try printer.append("Package Found! - {s}.json\n\n", .{package_name}, .{ .color = .green });
        try logger.infof("Package.init: package {s} found", .{package_name}, @src());

        const versions = parsed_package.value.versions;
        if (versions.len == 0) {
            printer.append("\nPackage has no version!\n", .{}, .{ .color = .red }) catch {};
            try logger.warnf("Package.init: package {s} has no versions", .{package_name}, @src());
            return error.PackageVersion;
        }

        const target_version = package_version orelse versions[0].version;
        try printer.append("Getting the package version...\n", .{}, .{});
        try printer.append("Target Version: ", .{}, .{});

        if (package_version) |v| {
            try printer.append("{s}", .{v}, .{});
        } else {
            try printer.append("/ (no version specified, using latest)", .{}, .{});
        }
        try printer.append("\n\n", .{}, .{});
        try logger.debugf("Package.init: target version is {s}", .{target_version}, @src());

        var check_selected: ?Structs.Packages.PackageVersions = null;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, target_version)) {
                check_selected = v;
                break;
            }
        }

        const selected = check_selected orelse {
            try printer.append("Package version was not found...\n\n", .{}, .{ .color = .red });
            try logger.warnf("Package.init: version {s} not found for package {s}", .{ target_version, package_name }, @src());
            return error.PackageVersion;
        };

        try printer.append("Package version found!\n\n", .{}, .{ .color = .green });
        try logger.infof("Package.init: selected version {s} for package {s}", .{ target_version, package_name }, @src());

        // Create hash
        const hash = try Hash.hashData(allocator, selected.url);
        try logger.debugf("Package.init: computed hash for {s}@{s}", .{ package_name, target_version }, @src());

        const id = try std.fmt.allocPrint(allocator, "{s}@{s}", .{
            package_name,
            target_version,
        });

        return Package{
            .allocator = allocator,
            .json = json,
            .manifest = manifest,
            .package_name = package_name,
            .package_version = target_version,
            .package_hash = hash,
            .package = selected,
            .printer = printer,
            .paths = paths,
            .id = id,
        };
    }

    pub fn deinit(self: *Package) void {
        const logger = Logger.get();
        logger.debugf("Package.deinit: freeing package {s}", .{self.id}, @src()) catch {};
        self.allocator.free(self.id);
        self.allocator.free(self.package_hash);
    }

    fn getPackagePathsAmount(self: *Package) !usize {
        const logger = Logger.get();
        try logger.debugf("getPackagePathsAmount: checking package {s}", .{self.id}, @src());

        var package_manifest = try self.manifest.readManifest(
            Structs.Manifests.PackagesManifest,
            self.paths.pkg_manifest,
        );
        defer package_manifest.deinit();

        var package_paths_amount: usize = 0;
        for (package_manifest.value.packages) |package| {
            if (std.mem.eql(u8, package.name, self.id)) {
                package_paths_amount = package.paths.len;
                break;
            }
        }

        try logger.debugf("getPackagePathsAmount: package {s} has {d} paths", .{ self.id, package_paths_amount }, @src());
        return package_paths_amount;
    }

    pub fn deletePackage(self: *Package, force: bool) !void {
        const logger = Logger.get();
        try logger.debugf("deletePackage: attempting to delete {s}", .{self.id}, @src());

        var buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}",
            .{ self.paths.pkg_root, self.id },
        );

        const amount = try self.getPackagePathsAmount();
        if (amount > 0 and !force) {
            try self.printer.append("\nWARNING: Atleast 1 project is using {s} [{d}]. Uninstalling it globally now might have serious consequences.\n\n", .{ self.id, amount }, .{ .color = .red });
            try self.printer.append("Use - if you do not care\n $ zep fglobal-uninstall [target]@[version]\n\n", .{}, .{ .color = .yellow });
            try logger.warnf("deletePackage: package {s} is used by {d} projects, aborting deletion", .{ self.id, amount }, @src());
            return;
        }

        if (Fs.existsDir(path)) {
            try Fs.deleteTreeIfExists(path);
            try logger.infof("deletePackage: deleted package directory {s}", .{path}, @src());
        }
    }
};

fn absDiff(x: usize, y: usize) usize {
    return @as(usize, @abs(@as(i64, @intCast(x)) - @as(i64, @intCast(y))));
}

fn hammingDistance(s1: []const u8, s2: []const u8) usize {
    const min_len = if (s1.len < s2.len) s1.len else s2.len;
    var dist = absDiff(s1.len, s2.len);
    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        if (s1[i] != s2[i]) dist += 1;
    }
    return dist;
}
