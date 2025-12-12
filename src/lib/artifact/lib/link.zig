const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

/// Updates the symbolic link to point to the currently active Artifact installation
pub fn updateLink(
    artifact_type: Structs.Extras.ArtifactType,
    paths: *Constants.Paths.Paths,
) !void {
    var allocator = std.heap.page_allocator;
    // Load manifest and get absolute path
    const manifest = try Manifest.readManifest(
        Structs.Manifests.ArtifactManifest,
        allocator,
        if (artifact_type == .zig) paths.zig_manifest else paths.zep_manifest,
    );
    if (manifest.value.path.len == 0) {
        if (artifact_type == .zig) {
            std.debug.print("\nManifest path is not defined! Use\n $ zep zig switch <zig-version>\nTo fix!\n", .{});
        } else {
            std.debug.print("\nManifest path is not defined! Use\n $ zep zep switch <zep-version>\nTo fix!\n", .{});
        }
        return error.ManifestNotFound;
    }

    defer manifest.deinit();

    const absolute_path = try std.fs.realpathAlloc(allocator, manifest.value.path);
    defer allocator.free(absolute_path);

    if (builtin.os.tag == .windows) {
        const exe = try std.fmt.allocPrint(allocator, "{s}.exe", .{
            if (artifact_type == .zig) "zig" else "zep",
        });
        defer allocator.free(exe);

        const artifact_path = try std.fs.path.join(allocator, &.{ absolute_path, exe });
        defer allocator.free(artifact_path);
        if (!Fs.existsFile(artifact_path)) {
            if (artifact_type == .zig) {
                std.debug.print("\nZig file does not exists! {s}\n", .{artifact_path});
            } else {
                std.debug.print("\nZep file does not exists! {s}\n", .{artifact_path});
            }
            return error.ManifestNotFound;
        }

        const sym_link_path_directory = try std.fs.path.join(
            allocator,
            &.{
                if (artifact_type == .zig) paths.zig_root else paths.zep_root, "e",
            },
        );
        if (!Fs.existsDir(sym_link_path_directory)) {
            try std.fs.cwd().makePath(sym_link_path_directory);
        }

        const sym_link_path = try std.fs.path.join(
            allocator,
            &.{
                sym_link_path_directory,
                exe,
            },
        );
        defer allocator.free(sym_link_path);
        Fs.deleteFileIfExists(sym_link_path) catch {};
        Fs.deleteDirIfExists(sym_link_path) catch {};

        try std.fs.cwd().symLink(artifact_path, sym_link_path, .{ .is_directory = false });
    } else {
        var artifact_target: []const u8 = "zig";
        if (artifact_type == .zep) {
            artifact_target = "zeP";
            const check_exe_path = try std.fs.path.join(allocator, &.{ absolute_path, "zeP" });
            defer allocator.free(check_exe_path);
            if (!Fs.existsFile(check_exe_path)) {
                artifact_target = "zep";
            }
        }

        const artifact_path = try std.fs.path.join(allocator, &.{ absolute_path, artifact_target });
        defer allocator.free(artifact_path);

        if (!Fs.existsFile(artifact_path)) {
            if (artifact_type == .zig) {
                std.debug.print("\nZig file does not exists! {s}\n", .{artifact_path});
            } else {
                std.debug.print("\nZep file does not exists! {s}\n", .{artifact_path});
            }
            return error.ManifestNotFound;
        }

        const artifact_target_file = try Fs.openFile(artifact_path);
        defer artifact_target_file.close();
        try artifact_target_file.chmod(0o755);

        const sym_link_path = try std.fs.path.join(allocator, &.{ paths.base, "bin", if (artifact_type == .zig) "zig" else "zep" });
        defer allocator.free(sym_link_path);
        Fs.deleteFileIfExists(sym_link_path) catch {};
        Fs.deleteDirIfExists(sym_link_path) catch {};

        try std.fs.cwd().symLink(artifact_path, sym_link_path, .{ .is_directory = false });
    }
}
