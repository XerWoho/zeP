const std = @import("std");
const builtin = @import("builtin");

const Link = @import("lib/link.zig");

pub const ArtifactSwitcher = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json;

const Context = @import("context");

const LatestArtifact = struct {
    version_name: []const u8,
    target_name: []const u8,
};

/// Handles switching between installed Artifact versions
ctx: *Context,

pub fn init(ctx: *Context) ArtifactSwitcher {
    return ArtifactSwitcher{
        .ctx = ctx,
    };
}

pub fn deinit(_: *ArtifactSwitcher) void {
    // currently no deinit required
}

/// Switch active Artifact version
/// Updates manifest and system PATH
pub fn switchVersion(
    self: *ArtifactSwitcher,
    name: []const u8,
    version: []const u8,
    target: []const u8,
    artifact_type: Structs.Extras.ArtifactType,
) Errors.Artifact!void {
    const os_name = @tagName(builtin.os.tag);
    if (!std.mem.containsAtLeast(u8, target, 1, os_name)) {
        return Errors.Artifact.InvalidOS;
    }

    // Update manifest with new version
    self.ctx.printer.append(
        "Modifying Manifest...\n",
        .{},
        .{
            .verbosity = 2,
        },
    );
    const path = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "d",
        version,
        target,
    });

    defer self.ctx.allocator.free(path);

    self.ctx.manifest.writeManifest(
        Structs.Manifests.Artifact,
        if (artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
        Structs.Manifests.Artifact{ .name = name, .path = path },
    ) catch return Errors.Artifact.ManifestFailed;

    // Update zep.lock
    blk: {
        if (artifact_type == .zep) break :blk;

        // all need to match for it to be in a zep project
        if (!Fs.existsFile(Constants.Default.package_files.lock)) break :blk;
        var lock = self.ctx.manifest.readManifest(
            Structs.ZepFiles.Lock,
            Constants.Default.package_files.lock,
        ) catch return Errors.Artifact.ManifestFailed;
        defer lock.deinit();

        lock.value.root.zig_version = version;
        self.ctx.manifest.writeManifest(
            Structs.ZepFiles.Lock,
            Constants.Default.package_files.lock,
            lock.value,
        ) catch return Errors.Artifact.LockFailed;
        break :blk;
    }

    self.ctx.printer.append(
        "Manifests up to date!\n",
        .{},
        .{},
    );

    // Update system PATH to point to new version
    self.ctx.printer.append(
        "Switching to installed version...\n",
        .{},
        .{},
    );
    try Link.updateLink(artifact_type, self.ctx);

    self.ctx.printer.append(
        "Switched to installed version successfully!\n",
        .{},
        .{ .color = .green },
    );
}

/// Find Latest artifact version
/// except skip_version
pub fn getLatestVersionExcept(self: *ArtifactSwitcher, artifact_type: Structs.Extras.ArtifactType, skip_version: []const u8) Errors.Artifact!LatestArtifact {
    // Update manifest with new version
    const artifact_root_path = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig)
            self.ctx.paths.zig_root
        else
            self.ctx.paths.zep_root,
        "d",
    });
    defer self.ctx.allocator.free(artifact_root_path);

    const open_artifact = Fs.openDir(artifact_root_path) catch return Errors.Artifact.DirFailed;
    var open_artifact_iter = open_artifact.iterate();

    var open_artifact_version: std.fs.Dir.Entry = undefined;
    while (true) {
        const temp = open_artifact_iter.next() catch return Errors.Artifact.IterFailed;
        open_artifact_version = temp orelse return Errors.Artifact.IterFailed;

        if (!std.mem.eql(u8, open_artifact_version.name, skip_version))
            break;
    }

    const version_name = try self.ctx.allocator.dupe(u8, open_artifact_version.name);
    const entry_version = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig)
            self.ctx.paths.zig_root
        else
            self.ctx.paths.zep_root,
        "d",
        version_name,
    });
    defer self.ctx.allocator.free(entry_version);

    var open_version = Fs.openDir(entry_version) catch return Errors.Artifact.DirFailed;
    defer open_version.close();

    var open_entry = open_version.iterate();
    const temp = open_entry.next() catch return Errors.Artifact.IterFailed;
    const target_entry = temp orelse return Errors.Artifact.InvalidVersion;
    const target_name = try self.ctx.allocator.dupe(u8, target_entry.name);

    return LatestArtifact{ .version_name = version_name, .target_name = target_name };
}
