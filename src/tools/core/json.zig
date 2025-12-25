const std = @import("std");

pub const Json = @This();

const Logger = @import("logger");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Manifest = @import("manifest.zig");

/// Simple Json parsing and
/// writing into files.
allocator: std.mem.Allocator,
paths: Constants.Paths.Paths,

pub fn init(
    allocator: std.mem.Allocator,
    paths: Constants.Paths.Paths,
) !Json {
    const logger = Logger.get();
    try logger.info("Json: init", @src());
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
    try logger.infof("parseJsonFromFile: reading {s}", .{path}, @src());

    if (!Fs.existsFile(path)) {
        try logger.warnf("parseJsonFromFile: file not found {s}", .{path}, @src());
        return error.FileNotFound;
    }

    var file = try Fs.openFile(path);
    defer file.close();

    const data = try file.readToEndAlloc(self.allocator, max);
    const parsed = try std.json.parseFromSlice(T, self.allocator, data, .{});
    try logger.infof("parseJsonFromFile: parsed {s} successfully", .{path}, @src());
    return parsed;
}

pub fn writePretty(
    self: *Json,
    path: []const u8,
    data: anytype,
) !void {
    const logger = Logger.get();
    try logger.infof("writePretty: writing to {s}", .{path}, @src());

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
