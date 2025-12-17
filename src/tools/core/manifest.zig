const std = @import("std");

const Logger = @import("logger");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("json.zig").Json;

pub const Manifest = struct {
    allocator: std.mem.Allocator,
    json: *Json,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        json: *Json,
        paths: *Constants.Paths.Paths,
    ) !Manifest {
        const logger = Logger.get();
        try logger.debug("Manifest: init", @src());
        return .{
            .allocator = allocator,
            .json = json,
            .paths = paths,
        };
    }

    pub fn writeManifest(
        self: *Manifest,
        comptime ManifestType: type,
        path: []const u8,
        manifest: ManifestType,
    ) !void {
        const logger = Logger.get();
        try logger.debugf("writeManifest: writing manifest to {s}", .{path}, @src());

        try Fs.deleteFileIfExists(path);

        const jsonStr = try std.json.Stringify.valueAlloc(self.allocator, manifest, .{ .whitespace = .indent_tab });
        defer self.allocator.free(jsonStr);

        const f = try Fs.openOrCreateFile(path);
        defer f.close();

        _ = try f.write(jsonStr);
        try logger.infof("writeManifest: successfully wrote manifest to {s}", .{path}, @src());
    }

    pub fn readManifest(
        self: *Manifest,
        comptime ManifestType: type,
        path: []const u8,
    ) !std.json.Parsed(ManifestType) {
        const logger = Logger.get();
        try logger.debugf("readManifest: reading manifest from {s}", .{path}, @src());

        if (!Fs.existsFile(path)) {
            try logger.warnf("readManifest: file not found, writing default manifest {s}", .{path}, @src());
            const default_manifest: ManifestType = .{};
            try self.writeManifest(ManifestType, path, default_manifest);
        }

        const f = try Fs.openFile(path);
        defer f.close();

        const data = try f.readToEndAlloc(self.allocator, 10 * Constants.Default.mb);
        const parsed = std.json.parseFromSlice(ManifestType, self.allocator, data, .{}) catch {
            try logger.warnf("readManifest: parse failed, deleting corrupted file {s}", .{path}, @src());
            try Fs.deleteFileIfExists(path);
            return try self.readManifest(ManifestType, path);
        };

        try logger.debugf("readManifest: successfully read and parsed manifest {s}", .{path}, @src());
        return parsed;
    }

    fn stringInArray(haystack: [][]const u8, needle: []const u8) bool {
        for (haystack) |h| {
            if (std.mem.eql(u8, h, needle)) return true;
        }
        return false;
    }

    pub fn addPathToManifest(
        self: *Manifest,
        package_id: []const u8,
        linked_path: []const u8,
    ) !void {
        const logger = Logger.get();
        try logger.debugf("addPathToManifest: package={s} path={s}", .{ package_id, linked_path }, @src());

        var package_manifest = try self.readManifest(
            Structs.Manifests.PackagesManifest,
            self.paths.pkg_manifest,
        );
        defer package_manifest.deinit();

        var list = try std.ArrayList(Structs.Manifests.PackagePaths).initCapacity(self.allocator, 10);
        defer list.deinit(self.allocator);

        var list_path = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        defer list_path.deinit(self.allocator);

        for (package_manifest.value.packages) |p| {
            if (std.mem.eql(u8, p.name, package_id)) {
                for (p.paths) |path| try list_path.append(self.allocator, path);
                continue;
            }
            try list.append(self.allocator, p);
        }

        if (!stringInArray(list_path.items, linked_path)) {
            try list_path.append(self.allocator, linked_path);
            try logger.infof("addPathToManifest: added new path {s} for package {s}", .{ linked_path, package_id }, @src());
        }

        try list.append(self.allocator, Structs.Manifests.PackagePaths{
            .name = package_id,
            .paths = list_path.items,
        });

        package_manifest.value.packages = list.items;

        try self.json.writePretty(self.paths.pkg_manifest, package_manifest.value);
        try logger.debugf("addPathToManifest: manifest updated for package {s}", .{package_id}, @src());
    }

    pub fn removePathFromManifest(
        self: *Manifest,
        package_id: []const u8,
        linked_path: []const u8,
    ) !void {
        const logger = Logger.get();
        try logger.debugf("removePathFromManifest: package={s} path={s}", .{ package_id, linked_path }, @src());

        var package_manifest = try self.readManifest(
            Structs.Manifests.PackagesManifest,
            self.paths.pkg_manifest,
        );
        defer package_manifest.deinit();

        var list = try std.ArrayList(Structs.Manifests.PackagePaths).initCapacity(self.allocator, 10);
        defer list.deinit(self.allocator);

        var list_path = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        defer list_path.deinit(self.allocator);

        for (package_manifest.value.packages) |package_paths| {
            if (std.mem.eql(u8, package_paths.name, package_id)) {
                for (package_paths.paths) |path| {
                    if (std.mem.eql(u8, path, linked_path)) {
                        try logger.infof("removePathFromManifest: removing path {s} from package {s}", .{ path, package_id }, @src());
                        continue;
                    }
                    try list_path.append(self.allocator, path);
                }
                continue;
            }
            try list.append(self.allocator, package_paths);
        }

        if (list_path.items.len > 0) {
            try list.append(self.allocator, Structs.Manifests.PackagePaths{ .name = package_id, .paths = list_path.items });
            try logger.debugf("removePathFromManifest: updated manifest for package {s}", .{package_id}, @src());
        } else {
            var buf: [128]u8 = undefined;
            const package_path = try std.fmt.bufPrint(&buf, "{s}/{s}/", .{ self.paths.pkg_root, package_id });
            if (Fs.existsDir(package_path)) {
                Fs.deleteTreeIfExists(package_path) catch {};
                try logger.infof("removePathFromManifest: deleted empty package directory {s}", .{package_path}, @src());
            }
        }

        package_manifest.value.packages = list.items;
        try self.json.writePretty(self.paths.pkg_manifest, package_manifest.value);
        try logger.debugf("removePathFromManifest: manifest finalized for package {s}", .{package_id}, @src());
    }
};
