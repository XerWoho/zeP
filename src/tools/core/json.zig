const std = @import("std");

const Logger = @import("logger");
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
        const logger = Logger.get();
        try logger.debug("Json: init", @src());
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
        const logger = Logger.get();
        try logger.debugf("parseJsonFromFile: reading {s}", .{path}, @src());

        if (!Fs.existsFile(path)) {
            try logger.warnf("parseJsonFromFile: file not found {s}", .{path}, @src());
            return error.FileNotFound;
        }

        var file = try Fs.openFile(path);
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, max);
        const parsed = try std.json.parseFromSlice(T, self.allocator, data, .{});
        try logger.debugf("parseJsonFromFile: parsed {s} successfully", .{path}, @src());
        return parsed;
    }

    pub fn writePretty(
        self: *Json,
        path: []const u8,
        data: anytype,
    ) !void {
        const logger = Logger.get();
        try logger.debugf("writePretty: writing to {s}", .{path}, @src());

        const str = try std.json.Stringify.valueAlloc(
            self.allocator,
            data,
            .{ .whitespace = .indent_2 },
        );

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        _ = try file.write(str);
        try logger.infof("writePretty: successfully wrote {s}", .{path}, @src());
    }

    pub fn parsePackage(self: *Json, package_name: []const u8) !std.json.Parsed(Structs.Packages.PackageStruct) {
        const logger = Logger.get();
        try logger.debugf("parsePackage: fetching package {s}", .{package_name}, @src());

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var buf: [128]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &buf,
            "https://zep.run/packages/{s}.json",
            .{package_name},
        );
        const uri = try std.Uri.parse(url);

        var body = std.Io.Writer.Allocating.init(self.allocator);
        const fetched = try client.fetch(std.http.Client.FetchOptions{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &body.writer,
        });

        if (fetched.status == .not_found) {
            try logger.warnf("parsePackage: package not found online {s}", .{package_name}, @src());

            var local_path_buf: [128]u8 = undefined;
            const local_path = try std.fmt.bufPrint(
                &local_path_buf,
                "{s}/{s}.json",
                .{ self.paths.custom, package_name },
            );
            if (!Fs.existsFile(local_path)) {
                try logger.warnf("parsePackage: package not found locally {s}", .{local_path}, @src());
                return error.PackageNotFound;
            }

            const parsed = try self.parseJsonFromFile(Structs.Packages.PackageStruct, local_path, Constants.Default.mb * 10);
            try logger.debugf("parsePackage: loaded package from local file {s}", .{local_path}, @src());
            return parsed;
        }

        const data = body.written();
        const parsed = try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.allocator, data, .{});
        try logger.debugf("parsePackage: successfully fetched and parsed {s} from URL", .{url}, @src());
        return parsed;
    }
};
