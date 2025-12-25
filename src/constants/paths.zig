const std = @import("std");
const builtin = @import("builtin");

/// Returns absolute paths of specific
/// operating system.
pub fn paths(allocator: std.mem.Allocator) !Paths {
    var base: []const u8 = undefined;

    if (builtin.os.tag == .windows) {
        base = "C:\\Users\\Public\\AppData\\Local";
    } else if (builtin.os.tag == .linux) {
        const home = std.posix.getenv("HOME") orelse return error.MissingHome;
        base = try std.fs.path.join(allocator, &.{ home, ".local" });
    } else if (builtin.os.tag == .macos) {
        const home = std.posix.getenv("HOME") orelse return error.MissingHome;
        base = try std.fs.path.join(allocator, &.{ home, "Library", "Application Support" });
    } else {
        const home = std.posix.getenv("HOME") orelse return error.MissingHome;
        base = home;
    }
    return .{
        .allocator = allocator,
        .base = base,
        .root = try std.fs.path.join(allocator, &.{ base, "zeP" }),
        .prebuilt = try std.fs.path.join(allocator, &.{ base, "zeP", "prebuilt" }),
        .cached = try std.fs.path.join(allocator, &.{ base, "zeP", "cached" }),
        .custom = try std.fs.path.join(allocator, &.{ base, "zeP", "custom" }),

        .pkg_root = try std.fs.path.join(allocator, &.{ base, "zeP", "pkg" }),
        .zig_root = try std.fs.path.join(allocator, &.{ base, "zeP", "zig" }),
        .zep_root = try std.fs.path.join(allocator, &.{ base, "zeP", "zep" }),
        .logs_root = try std.fs.path.join(allocator, &.{ base, "zeP", "logs" }),
        .auth_root = try std.fs.path.join(allocator, &.{ base, "zeP", "auth" }),

        .pkg_manifest = try std.fs.path.join(allocator, &.{ base, "zeP", "pkg", "manifest.json" }),
        .zig_manifest = try std.fs.path.join(allocator, &.{ base, "zeP", "zig", "manifest.json" }),
        .zep_manifest = try std.fs.path.join(allocator, &.{ base, "zeP", "zep", "manifest.json" }),
        .auth_manifest = try std.fs.path.join(allocator, &.{ base, "zeP", "auth", "manifest.json" }),
    };
}

pub const Paths = struct {
    allocator: std.mem.Allocator,

    base: []const u8,
    root: []const u8,
    prebuilt: []const u8,
    custom: []const u8,
    cached: []const u8,

    pkg_root: []const u8,
    zig_root: []const u8,
    zep_root: []const u8,
    logs_root: []const u8,
    auth_root: []const u8,

    pkg_manifest: []const u8,
    zig_manifest: []const u8,
    zep_manifest: []const u8,
    auth_manifest: []const u8,

    pub fn deinit(self: *Paths) void {
        // self.allocator.free(self.base);
        self.allocator.free(self.root);
        self.allocator.free(self.prebuilt);
        self.allocator.free(self.custom);
        self.allocator.free(self.cached);

        self.allocator.free(self.pkg_root);
        self.allocator.free(self.zig_root);
        self.allocator.free(self.zep_root);
        self.allocator.free(self.logs_root);
        self.allocator.free(self.auth_root);

        self.allocator.free(self.pkg_manifest);
        self.allocator.free(self.zig_manifest);
        self.allocator.free(self.zep_manifest);
        self.allocator.free(self.auth_manifest);
    }
};
