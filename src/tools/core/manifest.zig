const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("json.zig").Json;

/// Writing any type of Manifest into
/// any path.
pub fn writeManifest(comptime ManifestType: type, allocator: std.mem.Allocator, path: []const u8, manifest: ManifestType) !void {
    try Fs.deleteFileIfExists(path);

    const jsonStr = try std.json.stringifyAlloc(allocator, manifest, .{ .whitespace = .indent_tab });
    defer allocator.free(jsonStr);

    // Write to manifest file
    const f = try Fs.openOrCreateFile(path);
    defer f.close();
    _ = try f.write(jsonStr);
}

/// Reading any type of Manifest from
/// any path.
pub fn readManifest(comptime ManifestType: type, allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(ManifestType) {
    if (!Fs.existsFile(path)) {
        const default_manifest: ManifestType = .{}; // this applies all default values
        try writeManifest(ManifestType, allocator, path, default_manifest);
    }

    const f = try Fs.openFile(path);
    defer f.close();

    const data = try f.readToEndAlloc(allocator, 10 * Constants.Default.mb);
    const parsed = std.json.parseFromSlice(ManifestType, allocator, data, .{}) catch {
        try Fs.deleteFileIfExists(path);
        return try readManifest(ManifestType, allocator, path);
    };

    return parsed;
}

/// Check if an array of strings, contains a specific
/// string
fn stringInArray(haystack: [][]const u8, needle: []const u8) bool {
    for (haystack) |h| {
        if (std.mem.eql(u8, h, needle)) return true;
    }
    return false;
}

/// Adds a symbolic link path into the manifest
pub fn addPathToManifest(
    json: *Json,
    package_id: []const u8,
    linked_path: []const u8,
    paths: *Constants.Paths.Paths,
) !void {
    const allocator = std.heap.page_allocator;

    var package_manifest = try readManifest(Structs.Manifests.PackagesManifest, allocator, paths.pkg_manifest);
    defer package_manifest.deinit();

    var list = std.ArrayList(Structs.Manifests.PackagePaths).init(allocator);
    defer list.deinit();

    var list_path = std.ArrayList([]const u8).init(allocator);
    defer list_path.deinit();

    for (package_manifest.value.packages) |p| {
        if (std.mem.eql(u8, p.name, package_id)) {
            for (p.paths) |path| try list_path.append(path);
            continue;
        }
        try list.append(p);
    }
    if (!stringInArray(list_path.items, linked_path)) try list_path.append(linked_path);
    try list.append(Structs.Manifests.PackagePaths{ .name = package_id, .paths = list_path.items });
    package_manifest.value.packages = list.items;

    try json.writePretty(paths.pkg_manifest, package_manifest.value);
}

/// Remove a symbolic link path from the manifest
pub fn removePathFromManifest(
    json: *Json,
    package_name: []const u8,
    package_id: []const u8,
    linked_path: []const u8,
    paths: *Constants.Paths.Paths,
) !void {
    _ = package_name;

    const allocator = std.heap.page_allocator;
    var package_manifest = try readManifest(Structs.Manifests.PackagesManifest, allocator, paths.pkg_manifest);
    defer package_manifest.deinit();

    var list = std.ArrayList(Structs.Manifests.PackagePaths).init(allocator);
    defer list.deinit();

    var list_path = std.ArrayList([]const u8).init(allocator);
    defer list_path.deinit();

    for (package_manifest.value.packages) |package_paths| {
        if (std.mem.eql(u8, package_paths.name, package_id)) {
            for (package_paths.paths) |path| {
                if (std.mem.eql(u8, path, linked_path)) continue;
                try list_path.append(path);
            }
            continue;
        }
        try list.append(package_paths);
    }

    if (list_path.items.len > 0) {
        try list.append(Structs.Manifests.PackagePaths{ .name = package_id, .paths = list_path.items });
    } else {
        const package_path = try std.fmt.allocPrint(allocator, "{s}/{s}/", .{ paths.pkg_root, package_id });
        defer allocator.free(package_path);
        if (Fs.existsDir(package_path)) {
            Fs.deleteTreeIfExists(package_path) catch {};
        }
    }

    package_manifest.value.packages = list.items;
    try json.writePretty(paths.pkg_manifest, package_manifest.value);
}
