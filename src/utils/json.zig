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

    pub fn parseJsonFromFile(
        self: *Json,
        comptime T: type,
        path: []const u8,
        max: usize,
    ) !?std.json.Parsed(T) {
        if (!UtilsFs.checkFileExists(path))
            return null;

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, max);
        return try std.json.parseFromSlice(T, self.allocator, data, .{});
    }

    pub fn writePretty(
        self: *Json,
        path: []const u8,
        data: anytype,
    ) !void {
        const str = try std.json.stringifyAlloc(
            self.allocator,
            data,
            .{ .whitespace = .indent_2 },
        );

        // create or truncate
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        _ = try file.write(str);
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

        return try self.parseJsonFromFile(Structs.PackageStruct, localPath, MAX_JSON_SIZE);
    }
};
