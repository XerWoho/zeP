const std = @import("std");

const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Hash = @import("hash.zig");
const Manifest = @import("manifest.zig");
const Json = @import("json.zig").Json;

/// Handles Packages, returns null if package is not found.
/// Rolls back to latest version if none was specified.
/// Hashes are generated on init.
pub const Package = struct {
    allocator: std.mem.Allocator,
    json: *Json,
    paths: *Constants.Paths.Paths,

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
        package_name: []const u8,
        package_version: ?[]const u8,
    ) !Package {
        try printer.append("Finding the package...\n", .{}, .{});

        // Load package manifest
        const parsed_package = try json.parsePackage(package_name);
        defer parsed_package.deinit();

        try printer.append("Package Found! - {s}.json\n\n", .{package_name}, .{ .color = .green });

        const versions = parsed_package.value.versions;
        if (versions.len == 0) {
            printer.append("\nPackage has no version!\n", .{}, .{ .color = .red }) catch {};
            return error.PackageVersion;
        }

        // Pick target version
        const target_version = package_version orelse versions[0].version;

        try printer.append("Getting the package version...\n", .{}, .{});
        try printer.append("Target Version: ", .{}, .{});

        if (package_version) |v| {
            try printer.append("{s}", .{v}, .{});
        } else {
            try printer.append("/ (no version specified, using latest)", .{}, .{});
        }
        try printer.append("\n\n", .{}, .{});

        // Find version struct
        var check_selected: ?Structs.Packages.PackageVersions = null;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, target_version)) {
                check_selected = v;
                break;
            }
        }

        const selected = check_selected orelse {
            try printer.append("Package version was not found...\n\n", .{}, .{ .color = .red });
            return error.PackageVersion;
        };

        try printer.append("Package version found!\n\n", .{}, .{ .color = .green });

        // Create hash
        const hash = try Hash.hashData(allocator, selected.url);

        // Compute id
        const id = try std.fmt.allocPrint(allocator, "{s}@{s}", .{
            package_name,
            target_version,
        });

        return Package{
            .allocator = allocator,
            .json = json,
            .package_name = package_name,
            .package_version = target_version,
            .package_hash = hash,
            .package = selected,
            .printer = printer,
            .paths = paths,
            .id = id,
        };
    }

    pub fn deinit(_: *Package) void {}

    fn getPackagePathsAmount(self: *Package) !usize {
        var package_manifest = try Manifest.readManifest(
            Structs.Manifests.PackagesManifest,
            self.allocator,
            self.paths.pkg_manifest,
        );
        defer package_manifest.deinit();

        var package_paths_amount: usize = 0;
        for (package_manifest.value.packages) |package| {
            if (std.mem.eql(u8, package.name, self.id)) {
                package_paths_amount = package.paths.len;
                break;
            }
            continue;
        }

        return package_paths_amount;
    }

    pub fn deletePackage(self: *Package, force: bool) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.paths.pkg_root, self.id });
        defer self.allocator.free(path);

        const amount = try self.getPackagePathsAmount();
        if (amount > 0 and !force) {
            try self.printer.append("\nWARNING: Atleast 1 project is using {s} [{d}]. Uninstalling it globally now might have serious consequences.\n\n", .{ self.id, amount }, .{ .color = .red });
            try self.printer.append("Use - if you do not care\n $ zep fglobal-uninstall [target]@[version]\n\n", .{}, .{ .color = .yellow });
            return;
        }

        if (Fs.existsDir(path)) {
            try Fs.deleteTreeIfExists(path);
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
