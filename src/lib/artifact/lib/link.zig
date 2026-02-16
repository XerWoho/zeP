const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;

const Context = @import("context");
const Errors = @import("errors");

/// Updates the symbolic link to point to the currently active Artifact installation
pub fn updateLink(artifact_type: Structs.Extras.ArtifactType, ctx: *Context) Errors.Artifact!void {
    // Load manifest and get absolute path
    const manifest = ctx.manifest.readManifest(
        Structs.Manifests.Artifact,
        if (artifact_type == .zig) ctx.paths.zig_manifest else ctx.paths.zep_manifest,
    ) catch return Errors.Artifact.ManifestFailed;
    if (manifest.value.path.len == 0) return Errors.Artifact.ManifestFailed;

    defer manifest.deinit();

    const absolute_path = std.fs.realpathAlloc(ctx.allocator, manifest.value.path) catch return Errors.Artifact.OutOfMemory;
    defer ctx.allocator.free(absolute_path);

    if (builtin.os.tag == .windows) {
        const exe = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}.exe",
            .{
                if (artifact_type == .zig) "zig" else "zep",
            },
        );
        defer ctx.allocator.free(exe);

        const artifact_path = try std.fs.path.join(ctx.allocator, &.{ absolute_path, exe });
        defer ctx.allocator.free(artifact_path);
        if (!Fs.existsFile(artifact_path)) {
            ctx.printer.append(
                "{s} file does not exists! {s}\n",
                .{
                    if (artifact_type == .zig) "Zig" else "Zep", artifact_path,
                },
                .{},
            );
            return Errors.Artifact.FileFailed;
        }

        const sym_link_path = try std.fs.path.join(
            ctx.allocator,
            &.{
                ctx.paths.bin,
                exe,
            },
        );
        defer ctx.allocator.free(sym_link_path);
        Fs.deleteFileIfExists(sym_link_path) catch return Errors.Artifact.FileFailed;
        Fs.deleteDirIfExists(sym_link_path) catch return Errors.Artifact.DirFailed;

        std.fs.cwd().symLink(
            artifact_path,
            sym_link_path,
            .{ .is_directory = false },
        ) catch return Errors.Artifact.LinkingFailed;
    } else {
        if (!std.fs.has_executable_bit) return Errors.Artifact.InvalidOS;

        var artifact_target: []const u8 = "zig";
        if (artifact_type == .zep) {
            artifact_target = "zeP";
            const check_exe_path = try std.fs.path.join(ctx.allocator, &.{ absolute_path, "zeP" });
            defer ctx.allocator.free(check_exe_path);
            if (!Fs.existsFile(check_exe_path)) {
                artifact_target = "zep";
            }
        }

        const artifact_path = try std.fs.path.join(ctx.allocator, &.{ absolute_path, artifact_target });
        defer ctx.allocator.free(artifact_path);

        if (!Fs.existsFile(artifact_path)) {
            ctx.printer.append(
                "{s} file does not exists! {s}\n",
                .{
                    if (artifact_type == .zig) "Zig" else "Zep", artifact_path,
                },
                .{},
            );
            return Errors.Artifact.FileFailed;
        }

        const artifact_target_file = Fs.openFile(artifact_path) catch return Errors.Artifact.FileFailed;
        defer artifact_target_file.close();
        try artifact_target_file.chmod(0o755);

        const sym_link_path = try std.fs.path.join(
            ctx.allocator,
            &.{
                ctx.paths.bin,
                if (artifact_type == .zig) "zig" else "zep",
            },
        );
        defer ctx.allocator.free(sym_link_path);

        Fs.deleteFileIfExists(sym_link_path) catch return Errors.Artifact.FileFailed;
        Fs.deleteDirIfExists(sym_link_path) catch return Errors.Artifact.FileFailed;

        std.fs.cwd().symLink(
            artifact_path,
            sym_link_path,
            .{ .is_directory = false },
        ) catch return Errors.Artifact.LinkingFailed;
    }
}
