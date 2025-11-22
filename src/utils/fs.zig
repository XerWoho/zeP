const std = @import("std");

pub fn checkFileExists(path: []const u8) bool {
    const cwd = std.fs.cwd();
    var f = cwd.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    defer f.close();
    return true;
}

pub fn checkDirExists(path: []const u8) bool {
    const cwd = std.fs.cwd();
    var d = cwd.openDir(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    defer d.close();
    return true;
}

pub fn openCFile(path: []const u8) !std.fs.File {
    if (!checkFileExists(path)) {
        const parent = std.fs.path.dirname(path) orelse "";
        try std.fs.cwd().makePath(parent);
        return try std.fs.cwd().createFile(path, std.fs.File.CreateFlags{ .read = true });
    }
    return try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{ .mode = .read_write });
}

pub fn openFile(path: []const u8) !std.fs.File {
    if (!checkFileExists(path)) {
        _ = try std.fs.cwd().createFile(path, std.fs.File.CreateFlags{ .read = true });
    }
    return try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{ .mode = .read_write });
}

pub fn openCDir(path: []const u8) !std.fs.Dir {
    if (!checkDirExists(path)) {
        const parent = std.fs.path.dirname(path) orelse "";
        try std.fs.cwd().makePath(parent);
        _ = try std.fs.cwd().makeDir(path);
    }
    return try std.fs.cwd().openDir(path, std.fs.Dir.OpenDirOptions{ .iterate = true });
}

pub fn openDir(path: []const u8) !std.fs.Dir {
    if (!checkDirExists(path)) {
        _ = try std.fs.cwd().makeDir(path);
    }
    return try std.fs.cwd().openDir(path, std.fs.Dir.OpenDirOptions{ .iterate = true });
}

pub fn delFile(path: []const u8) !void {
    if (checkFileExists(path))
        try std.fs.cwd().deleteFile(path);
}

pub fn delDir(path: []const u8) !void {
    if (checkDirExists(path))
        try std.fs.cwd().deleteDir(path);
}

pub fn delTree(path: []const u8) !void {
    if (checkDirExists(path))
        try std.fs.cwd().deleteTree(path);
}
