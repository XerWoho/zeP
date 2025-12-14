const std = @import("std");
const Logger = @import("logger");

/// validates if a File exists
/// => Errors will return false
pub fn existsFile(path: []const u8) bool {
    const logger = Logger.get();
    const cwd = std.fs.cwd();
    var f = cwd.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            logger.infof("File does not exist: {s}", .{path}, @src()) catch {};
            return false;
        },
        else => {
            logger.infof("File check failed: {s}", .{path}, @src()) catch {};
            return false;
        },
    };
    defer f.close();
    logger.infof("File exists: {s}", .{path}, @src()) catch {};
    return true;
}

/// validates if a Dir exists
/// => Errors will return false
pub fn existsDir(path: []const u8) bool {
    const logger = Logger.get();
    const cwd = std.fs.cwd();
    var d = cwd.openDir(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            logger.infof("Dir does not exist: {s}", .{path}, @src()) catch {};
            return false;
        },
        else => {
            logger.infof("Dir check failed: {s}", .{path}, @src()) catch {};
            return false;
        },
    };
    defer d.close();
    logger.infof("Dir exists: {s}", .{path}, @src()) catch {};
    return true;
}

/// Checks if a File exists and creates it if it does not [THE WHOLE PATH]
pub fn openOrCreateFile(path: []const u8) !std.fs.File {
    const logger = Logger.get();
    if (!existsFile(path)) {
        const parent = std.fs.path.dirname(path) orelse "";
        if (parent.len > 0) try std.fs.cwd().makePath(parent);
        const f = try std.fs.cwd().createFile(path, std.fs.File.CreateFlags{ .read = true });
        try logger.infof("Created file: {s}", .{path}, @src());
        return f;
    }
    const f = try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{ .mode = .read_write });
    try logger.infof("Opened file: {s}", .{path}, @src());
    return f;
}

/// Checks if a File exists and creates it if it does not [NO PATH]
pub fn openFile(path: []const u8) !std.fs.File {
    const logger = Logger.get();
    if (!existsFile(path)) {
        const f = try std.fs.cwd().createFile(path, std.fs.File.CreateFlags{ .read = true });
        try logger.infof("Created file: {s}", .{path}, @src());
        return f;
    }
    const f = try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{ .mode = .read_write });
    try logger.infof("Opened file: {s}", .{path}, @src());
    return f;
}

/// Checks if a Dir exists and creates it if it does not [THE WHOLE PATH]
pub fn openOrCreateDir(path: []const u8) !std.fs.Dir {
    const logger = Logger.get();
    if (!existsDir(path)) {
        try std.fs.cwd().makePath(path);
        try logger.infof("Created dir path: {s}", .{path}, @src());
    }
    const d = try std.fs.cwd().openDir(path, std.fs.Dir.OpenOptions{ .iterate = true });
    try logger.infof("Opened dir: {s}", .{path}, @src());
    return d;
}

/// Checks if a Dir exists and creates it if it does not [NO PATH]
pub fn openDir(path: []const u8) !std.fs.Dir {
    const logger = Logger.get();
    if (!existsDir(path)) {
        try std.fs.cwd().makeDir(path);
        try logger.infof("Created dir: {s}", .{path}, @src());
    }
    const d = try std.fs.cwd().openDir(path, std.fs.Dir.OpenOptions{ .iterate = true });
    try logger.infof("Opened dir: {s}", .{path}, @src());
    return d;
}

/// Deletes file if it exists
pub fn deleteFileIfExists(path: []const u8) !void {
    const logger = Logger.get();
    if (existsFile(path)) {
        try std.fs.cwd().deleteFile(path);
        try logger.infof("Deleted file: {s}", .{path}, @src());
    }
}

/// Deletes dir [no tree] if it exists
pub fn deleteDirIfExists(path: []const u8) !void {
    const logger = Logger.get();
    if (existsDir(path)) {
        try std.fs.cwd().deleteDir(path);
        try logger.infof("Deleted dir: {s}", .{path}, @src());
    }
}

/// Deletes tree if it exists
pub fn deleteTreeIfExists(path: []const u8) !void {
    const logger = Logger.get();
    if (existsDir(path)) {
        try std.fs.cwd().deleteTree(path);
        try logger.infof("Deleted dir tree: {s}", .{path}, @src());
    }
}
