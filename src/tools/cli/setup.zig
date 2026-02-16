const std = @import("std");
const builtin = @import("builtin");

const Loggexr = @import("logger");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("printer.zig");

fn setupEnviromentPath(tmp_path: []const u8) !void {
    if (!std.fs.has_executable_bit) return;

    const sh_file =
        \\ #!/bin/bash
        \\ 
        \\ BIN="$HOME/.zep/bin"
        \\ export PATH="$BIN:$PATH"
        \\ grep -qxF "export PATH=\"$BIN:\$PATH\"" "$HOME/.bashrc" || echo "export PATH=\"$BIN:\$PATH\"" >> "$HOME/.bashrc"
    ;

    const tmp = try Fs.openOrCreateFile(tmp_path);
    defer {
        tmp.close();
        Fs.deleteFileIfExists(tmp_path) catch {};
    }

    const alloc = std.heap.page_allocator;
    _ = try tmp.write(sh_file);
    try tmp.chmod(0o755);

    var exec_cmd = std.process.Child.init(&.{ "bash", tmp_path }, alloc);
    _ = exec_cmd.spawnAndWait() catch {};
}

/// Runs on install.
/// Sets up basic folders for faster
/// usage.
pub fn setup(
    allocator: std.mem.Allocator,
    paths: *Constants.Paths.Paths,
    printer: *Printer,
) !void {
    const create_paths = [_][]const u8{
        paths.zep_root,
        paths.bin,
        paths.cached,
        paths.pkg_cached,
        paths.meta_cached,
        paths.pkg_root,
        paths.zig_root,
        paths.prebuilt,
        paths.custom,
        paths.auth_root,
        paths.logs_root,
    };
    for (create_paths) |p| {
        _ = Fs.openOrCreateDir(p) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    printer.append("Creating {s} Failed! (Admin Privelege required)\n", .{p}, .{});
                    return;
                },
                else => return,
            }
        };
    }

    if (builtin.os.tag != .linux) return;

    const tmp_path = try std.fs.path.join(allocator, &.{ paths.base, "temp" });
    const tmp_file = try std.fs.path.join(allocator, &.{ tmp_path, "tmp_exe" });

    defer {
        Fs.deleteTreeIfExists(tmp_path) catch {};

        allocator.free(tmp_file);
        allocator.free(tmp_path);
    }

    try setupEnviromentPath(tmp_file);
}
