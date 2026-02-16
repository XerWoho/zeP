const Extras = @import("extras.zig");
const Constants = @import("constants");
const builtin = @import("builtin");

pub const Build = struct {
    entry: []const u8 = "src/main.zig",
    target: []const u8 = if (builtin.os.tag == .windows)
        Constants.Default.default_targets.windows
    else
        Constants.Default.default_targets.linux,
};

pub const Command = struct {
    name: []const u8,
    cmd: []const u8,
};

pub const Root = struct {
    author: []const u8 = "",
    tags: [][]const u8 = &[_][]const u8{},
    zig_version: []const u8 = Constants.Default.zig_version,
    repo: []const u8 = "",
    name: []const u8 = "",
    cmd: []Command = &[_]Command{},
    description: []const u8 = "",
    version: []const u8 = "0.0.1",
    license: []const u8 = "",
    packages: [][]const u8 = &[_][]const u8{},
    dev_packages: [][]const u8 = &[_][]const u8{},
    build: Build = .{},
};

pub const Package = struct {
    name: []const u8,
    author: []const u8,
    install: []const u8,
    version: []const u8,
    hash: []const u8,
    source: []const u8,
    zig_version: []const u8,
    namespace: Extras.Namespaces = .zep,
};

pub const Lock = struct {
    schema: u8 = 2,
    root: Root = .{},
    packages: []Package = &[_]Package{},
    included_modules: [][]const u8 = &[_][]const u8{},
    excluded_modules: [][]const u8 = &[_][]const u8{},
};
