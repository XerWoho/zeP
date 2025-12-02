const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

/// Updates the symbolic link to point to the currently active Zig installation
pub fn updateLink() !void {
    const allocator = std.heap.page_allocator;
    var paths = try Constants.Paths.paths(allocator);
    defer paths.deinit();

    // Load manifest and get absolute path
    const manifest = try Manifest.readManifest(Structs.Manifests.ZepManifest, allocator, paths.zep_manifest);
    defer manifest.deinit();

    const absolute_path = try std.fs.realpathAlloc(allocator, manifest.value.path);
    defer allocator.free(absolute_path);

    const manifest_target = paths.zep_manifest;
    const open_manifest = try Fs.openFile(manifest_target);
    defer open_manifest.close();

    const read_open_manifest = try open_manifest.readToEndAlloc(allocator, Constants.Default.mb);
    const parsed_manifest: std.json.Parsed(Structs.Manifests.ZepManifest) = try std.json.parseFromSlice(Structs.Manifests.ZepManifest, allocator, read_open_manifest, .{});
    defer parsed_manifest.deinit();

    if (builtin.os.tag == .windows) {
        const zep_exe_path = try std.fmt.allocPrint(allocator, "{s}/zep.exe", .{parsed_manifest.value.path});
        defer allocator.free(zep_exe_path);

        const symbolic_link_zep_exe_directory = try std.fmt.allocPrint(allocator, "{s}/e", .{paths.zep_root});
        defer allocator.free(symbolic_link_zep_exe_directory);
        if (!Fs.existsDir(symbolic_link_zep_exe_directory)) {
            try std.fs.cwd().makePath(symbolic_link_zep_exe_directory);
        }

        const symbolic_link_zep_exe = try std.fmt.allocPrint(allocator, "{s}/zep.exe", .{symbolic_link_zep_exe_directory});
        defer allocator.free(symbolic_link_zep_exe);
        try Fs.deleteFileIfExists(symbolic_link_zep_exe);
        try std.fs.cwd().symLink(zep_exe_path, symbolic_link_zep_exe, .{ .is_directory = false });
    } else {
        const zep_exe_path = try std.fmt.allocPrint(allocator, "{s}/zeP", .{parsed_manifest.value.path});
        defer allocator.free(zep_exe_path);

        const zep_exe_target = try Fs.openFile(zep_exe_path);
        defer zep_exe_target.close();
        try zep_exe_target.chmod(0o755);

        const sym_link_path = try std.fs.path.join(allocator, &.{ paths.base, "bin", "zeP" });
        defer allocator.free(sym_link_path);

        try std.fs.cwd().symLink(zep_exe_path, sym_link_path, .{ .is_directory = false });
    }
}
