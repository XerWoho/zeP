const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const UtilsFs =
    @import("fs.zig");
const UtilsPackage =
    @import("package.zig");

const MAX_JSON_SIZE = 10 * 1024 * 1024; // 10 MB

pub const Json = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Json {
        return Json{ .allocator = allocator };
    }

    fn parse(self: *Json, path: []const u8) !?std.json.Parsed(Structs.PackageStruct) {
        const check = try UtilsFs.checkFileExists(path);
        if (!check) return null;

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, MAX_JSON_SIZE);
        const parsedData = try std.json.parseFromSlice(Structs.PackageStruct, self.allocator, data, .{});
        return parsedData;
    }

    pub fn parsePackage(self: *Json, packageName: []const u8) !?std.json.Parsed(Structs.PackageStruct) {
        const manifestTarget = Constants.ROOT_ZEP_ZEP_MANIFEST;
        const openManifest = try UtilsFs.openFile(manifestTarget);
        defer openManifest.close();

        const readOpenManifest = try openManifest.readToEndAlloc(self.allocator, 1024 * 1024);
        const parsedManifest = try std.json.parseFromSlice(Structs.ZepManifest, self.allocator, readOpenManifest, .{});
        defer parsedManifest.deinit();

        const localPath = try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}.json", .{ parsedManifest.value.path, packageName });
        defer self.allocator.free(localPath);

        const customPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ Constants.ROOT_ZEP_CUSTOM_PACKAGES, packageName });
        defer self.allocator.free(customPath);

        const localParsed = try self.parse(localPath);
        if (localParsed) |l| return l;
        const customParsed = try self.parse(customPath);
        if (customParsed) |c| return c;
        return null;
    }

    pub fn parsePkgJson(self: *Json) !?std.json.Parsed(Structs.PackageJsonStruct) {
        if (!try UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE))
            return null;

        var file = try UtilsFs.openFile(Constants.ZEP_PACKAGE_FILE);
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, MAX_JSON_SIZE);
        return try std.json.parseFromSlice(Structs.PackageJsonStruct, self.allocator, data, .{});
    }

    pub fn parseLockJson(self: *Json) !?std.json.Parsed(Structs.PackageLockStruct) {
        if (!try UtilsFs.checkFileExists(Constants.ZEP_LOCK_PACKAGE_FILE))
            return null;

        var file = try UtilsFs.openFile(Constants.ZEP_LOCK_PACKAGE_FILE);
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, MAX_JSON_SIZE);
        return try std.json.parseFromSlice(Structs.PackageLockStruct, self.allocator, data, .{});
    }

    pub fn parsePkgManifest(self: *Json) !?std.json.Parsed(Structs.PkgsManifest) {
        if (!try UtilsFs.checkFileExists(Constants.ROOT_ZEP_PKG_MANIFEST))
            return null;

        var file = try UtilsFs.openFile(Constants.ROOT_ZEP_PKG_MANIFEST);
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, MAX_JSON_SIZE);
        return try std.json.parseFromSlice(Structs.PkgsManifest, self.allocator, data, .{});
    }
};
