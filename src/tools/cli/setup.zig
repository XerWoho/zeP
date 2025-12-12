const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("printer.zig").Printer;

fn setupEnviromentPath(tmp_path: []const u8) !void {
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
        Fs.deleteFileIfExists(tmp_path) catch {};
    }

    const allocator = std.heap.page_allocator;
    _ = try tmp.write(sh_file);
    try tmp.chmod(0o755);

    var exec_cmd = std.process.Child.init(&.{ "bash", tmp_path }, allocator);
    _ = exec_cmd.spawnAndWait() catch {};
}

/// Runs on install.
/// Sets up basic folders for faster
/// usage.
pub fn setup(
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
) !void {
    const create_paths = [5][]const u8{
        paths.root,
        paths.zep_root,
        paths.zepped,
        paths.pkg_root,
        paths.zig_root,
    };
    for (create_paths) |p| {
        _ = Fs.openOrCreateDir(p) catch |err| {
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
    defer {
        Fs.deleteTreeIfExists(tmp_path) catch {};

        allocator.free(tmp_file);
        allocator.free(tmp_path);
    }

    try setupEnviromentPath(tmp_file);
}
