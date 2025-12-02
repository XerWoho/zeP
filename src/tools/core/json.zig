const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Manifest = @import("manifest.zig");

/// Simple Json parsing and
/// writing into files.
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
        if (!Fs.existsFile(path))
            return null;

        var file = try Fs.openFile(path);
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

    pub fn parsePackage(self: *Json, package_name: []const u8) !?std.json.Parsed(Structs.Packages.PackageStruct) {
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const manifest = try Manifest.readManifest(Structs.Manifests.ZepManifest, self.allocator, paths.zep_manifest);
        defer manifest.deinit();
        if (manifest.value.path.len == 0) {
            std.debug.print("\nManifest path is not defined! Use\n $ zep zep switch <current-version>\nOr re-install to fix!\n", .{});
            std.process.exit(0);
            return null;
        }

        var local_path = try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}.json", .{ manifest.value.path, package_name });
        defer self.allocator.free(local_path);
        if (!Fs.existsFile(local_path)) {
            local_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ paths.custom, package_name });
            if (!Fs.existsFile(local_path)) return error.PackageNotFound;
        }

        return try self.parseJsonFromFile(Structs.Packages.PackageStruct, local_path, Constants.Default.mb * 10);
    }
};
