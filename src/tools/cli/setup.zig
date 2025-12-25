const std = @import("std");
const builtin = @import("builtin");

const Logger = @import("logger");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("printer.zig");

fn setupEnviromentPath(tmp_path: []const u8) !void {
    const logger = Logger.get();
    try logger.info("setting up: enviroment path", @src());

    if (builtin.os.tag != .linux) return;
    const sh_file =
        \\ #!/bin/bash
        \\ 
        \\ USR_LOCAL_BIN="$HOME/.local/bin"
        \\ export PATH="$USR_LOCAL_BIN:$PATH"
        \\ grep -qxF "export PATH=\"$USR_LOCAL_BIN:\$PATH\"" "$HOME/.bashrc" || echo "export PATH=\"$USR_LOCAL_BIN:\$PATH\"" >> "$HOME/.bashrc"
    ;

    const tmp = try Fs.openOrCreateFile(tmp_path);
    defer {
        tmp.close();
        Fs.deleteFileIfExists(tmp_path) catch |err| {
            logger.warnf("setup enviroment path: could not remove temp file {s}, err={}", .{ tmp_path, err }, @src()) catch {
                @panic("Logger failed");
            };
        };
    }

    const alloc = std.heap.page_allocator;
    _ = try tmp.write(sh_file);
    try tmp.chmod(0o755);

    try logger.info("initilazing child", @src());
    var exec_cmd = std.process.Child.init(&.{ "bash", tmp_path }, alloc);
    _ = exec_cmd.spawnAndWait() catch |err| {
        try logger.errf("setup enviroment path: spawnAndWait failed, err={}", .{err}, @src());
    };

    try logger.info("setup enviroment path: setting enviroment path done", @src());
}

/// Runs on install.
/// Sets up basic folders for faster
/// usage.
pub fn setup(
    allocator: std.mem.Allocator,
    paths: *Constants.Paths.Paths,
    printer: *Printer,
) !void {
    const logger = Logger.get();
    try logger.info("setting up: create paths", @src());

    const create_paths = [5][]const u8{
        paths.root,
        paths.zep_root,
        paths.cached,
        paths.pkg_root,
        paths.zig_root,
    };
    for (create_paths) |p| {
        try logger.infof("setting paths: creating {s}", .{p}, @src());

        _ = Fs.openOrCreateDir(p) catch |err| {
            try logger.infof("setting paths: creating failed {s}, err={}", .{ p, err }, @src());
            switch (err) {
                error.AccessDenied => {
                    try printer.append("Creating {s} Failed! (Admin Privelege required)\n", .{p}, .{});
                    return;
                },
                else => return,
            }
        };
    }

    if (builtin.os.tag != .linux) return;

    const tmp_path = try std.fs.path.join(allocator, &.{ paths.root, "temp" });
    const tmp_file = try std.fs.path.join(allocator, &.{ tmp_path, "tmp_exe" });
    try logger.infof("setting paths: creating temp executeable {s}", .{tmp_file}, @src());

    defer {
        Fs.deleteTreeIfExists(tmp_path) catch {};

        allocator.free(tmp_file);
        allocator.free(tmp_path);
    }

    try setupEnviromentPath(tmp_file);
    try logger.info("setting paths: setup done", @src());
}
