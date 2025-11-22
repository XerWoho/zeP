const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const UtilsFs = @import("fs.zig");
const UtilsManifest = @import("manifest.zig");
const UtilsJson = @import("json.zig");

pub fn writeManifest(comptime ManifestType: type, allocator: std.mem.Allocator, path: []const u8, manifest: ManifestType) !void {
    _ = UtilsFs.delFile(path) catch {};

    const jsonStr = std.json.stringifyAlloc(allocator, manifest, .{ .whitespace = .indent_tab }) catch {
        @panic("Stringifying failed!");
    };
    defer allocator.free(jsonStr);

    // Write to manifest file
    const f = UtilsFs.openCFile(path) catch {
        std.debug.print("{s}\n", .{path});
        @panic("Stringifying failed!");
    };
    defer f.close();
    _ = f.write(jsonStr) catch {
        std.debug.print("{s}\n", .{jsonStr});
        @panic("Writing failed!");
    };
}

pub fn readManifest(comptime ManifestType: type, allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(ManifestType) {
    if (!UtilsFs.checkFileExists(path)) {
        const default_manifest: ManifestType = .{}; // this applies all default values
        try UtilsManifest.writeManifest(ManifestType, allocator, path, default_manifest);
    }

    const f = try UtilsFs.openFile(path);
    defer f.close();

    const data = try f.readToEndAlloc(allocator, 10 * 1024 * 1024);
    const parsed = try std.json.parseFromSlice(ManifestType, allocator, data, .{});
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
    json: *UtilsJson.Json,
    packageId: []const u8,
    linkedPath: []const u8,
) !void {
    const allocator = std.heap.page_allocator;

    var packageManifest = try UtilsManifest.readManifest(Structs.PackagesManifest, allocator, Constants.ROOT_ZEP_PKG_MANIFEST);
    defer packageManifest.deinit();

    var list = std.ArrayList(Structs.PkgManifest).init(allocator);
    defer list.deinit();

    var listPath = std.ArrayList([]const u8).init(allocator);
    defer listPath.deinit();

    for (packageManifest.value.packages) |p| {
        if (std.mem.eql(u8, p.name, packageId)) {
            for (p.paths) |path| try listPath.append(path);
            continue;
        }
        try list.append(p);
    }
    if (!stringInArray(listPath.items, linkedPath)) try listPath.append(linkedPath);
    try list.append(Structs.PkgManifest{ .name = packageId, .paths = listPath.items });
    packageManifest.value.packages = list.items;

    try json.writePretty(Constants.ROOT_ZEP_PKG_MANIFEST, packageManifest.value);
}

/// Remove a symbolic link path from the manifest
pub fn removePathFromManifest(
    json: *UtilsJson.Json,
    packageName: []const u8,
    packageId: []const u8,
    linkedPath: []const u8,
) !void {
    const allocator = std.heap.page_allocator;

    var packageManifest = try UtilsManifest.readManifest(Structs.PackagesManifest, allocator, Constants.ROOT_ZEP_PKG_MANIFEST);
    defer packageManifest.deinit();

    var list = std.ArrayList(Structs.PkgManifest).init(allocator);
    defer list.deinit();

    var listPath = std.ArrayList([]const u8).init(allocator);
    defer listPath.deinit();

    for (packageManifest.value.packages) |p| {
        if (std.mem.startsWith(u8, p.name, packageName)) {
            for (p.paths) |path| {
                if (std.mem.eql(u8, path, linkedPath)) continue;
                try listPath.append(path);
            }
            continue;
        }
        try list.append(p);
    }

    if (listPath.items.len > 0) {
        try list.append(Structs.PkgManifest{ .name = packageId, .paths = listPath.items });
    } else {
        const pkgPath = try std.fmt.allocPrint(allocator, "{s}/{s}/", .{ Constants.ROOT_ZEP_PKG_FOLDER, packageId });
        defer allocator.free(pkgPath);
        if (UtilsFs.checkDirExists(pkgPath)) {
            std.fs.cwd().deleteTree(pkgPath) catch {};
        }
    }

    packageManifest.value.packages = list.items;
    try json.writePretty(Constants.ROOT_ZEP_PKG_MANIFEST, packageManifest.value);
}
