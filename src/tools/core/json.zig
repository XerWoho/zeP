const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Manifest = @import("manifest.zig");

/// Simple Json parsing and
/// writing into files.
pub const Json = struct {
    allocator: std.mem.Allocator,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        paths: *Constants.Paths.Paths,
    ) !Json {
        return Json{
            .allocator = allocator,
            .paths = paths,
        };
    }

    pub fn parseJsonFromFile(
        self: *Json,
        comptime T: type,
        path: []const u8,
        max: usize,
    ) !std.json.Parsed(T) {
        if (!Fs.existsFile(path))
            return error.FileNotFound;

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

    pub fn parsePackage(self: *Json, package_name: []const u8) !std.json.Parsed(Structs.Packages.PackageStruct) {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var server_header_buffer: [Constants.Default.kb * 8]u8 = undefined;

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://zep.run/packages/{s}.json",
            .{package_name},
        );
        defer self.allocator.free(url);
        const uri = try std.Uri.parse(url);

        var req = try client.open(.GET, uri, .{ .server_header_buffer = &server_header_buffer });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();

        if (req.response.status == .not_found) {
            const local_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.paths.custom, package_name });
            if (!Fs.existsFile(local_path)) return error.PackageNotFound;
            const parsed = try self.parseJsonFromFile(Structs.Packages.PackageStruct, local_path, Constants.Default.mb * 10);
            return parsed;
        }

        var reader = req.reader();
        const body = try reader.readAllAlloc(self.allocator, Constants.Default.mb * 10);
        return try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.allocator, body, .{});
    }
};
