const std = @import("std");
const builtin = @import("builtin");

pub const ArtifactPruner = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

const Context = @import("context");

/// Lists installed Artifact versions
ctx: *Context,

pub fn init(
    ctx: *Context,
) ArtifactPruner {
    return ArtifactPruner{
        .ctx = ctx,
    };
}

pub fn deinit(_: *ArtifactPruner) void {
    // currently no deinit required
}

/// Prunes all Artifact versions
/// With zero targets
pub fn pruneVersions(self: *ArtifactPruner, artifact_type: Structs.Extras.ArtifactType) Errors.Artifact!void {
    self.ctx.logger.infof("Pruning {s}", .{if (artifact_type == .zig) "zig" else "zep"}, @src());

    const versions_directory = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "d",
    });
    defer self.ctx.allocator.free(versions_directory);

    if (!Fs.existsDir(versions_directory)) return Errors.Artifact.InvalidVersion;

    const manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Artifact,
        if (artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
    ) catch return Errors.Artifact.ManifestFailed;
    defer manifest.deinit();
    if (manifest.value.path.len == 0) return Errors.Artifact.ManifestFailed;

    var dir = Fs.openDir(versions_directory) catch return Errors.Artifact.DirFailed;
    defer dir.close();
    var it = dir.iterate();

    while (it.next() catch return Errors.Artifact.IterFailed) |entry| {
        if (entry.kind != .directory) continue;
        const version_path = try std.fs.path.join(self.ctx.allocator, &.{ versions_directory, entry.name });
        defer self.ctx.allocator.free(version_path);

        var version_directory = Fs.openDir(version_path) catch return Errors.Artifact.DirFailed;
        defer version_directory.close();

        var version_iterator = version_directory.iterate();
        var found_targets: bool = false;
        while (version_iterator.next() catch return Errors.Artifact.IterFailed) |_| {
            found_targets = true;
            break;
        }

        if (!found_targets) {
            Fs.deleteTreeIfExists(version_path) catch return Errors.Artifact.DirFailed;
        }
    }
}
