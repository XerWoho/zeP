const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const UtilsFs = @import("fs.zig");
const UtilsPackage = @import("package.zig");
const UtilsManifest = @import("manifest.zig");

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
        const manifest = try UtilsManifest.readManifest(Structs.ZepManifest, self.allocator, Constants.ROOT_ZEP_ZEP_MANIFEST);
        defer manifest.deinit();
        if (manifest.value.path.len == 0) {
            std.debug.print("\nManifest path is not defined! Use\n $ zep zep switch <current-version>\nOr re-install to fix!\n", .{});
            std.process.exit(0);
            return null;
        }

        const localPath = try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}.json", .{ manifest.value.path, packageName });
        defer self.allocator.free(localPath);

        return try self.parseJsonFromFile(Structs.PackageStruct, localPath, MAX_JSON_SIZE);
    }
};
