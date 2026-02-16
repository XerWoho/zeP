const std = @import("std");
const builtin = @import("builtin");

pub const ArtifactLister = @This();

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;

const Context = @import("context");
const Errors = @import("errors");

/// Lists installed Artifact versions
ctx: *Context,

pub fn init(ctx: *Context) ArtifactLister {
    return ArtifactLister{
        .ctx = ctx,
    };
}

pub fn deinit(_: *ArtifactLister) void {
    // currently no deinit required
}

fn extractVersionNameFromPath(_: *ArtifactLister, path: []const u8) []const u8 {
    const delimiter: []const u8 = if (builtin.os.tag == .windows) "\\" else "/";
    var segments = std.mem.splitAny(u8, path, delimiter);
    var last: []const u8 = &[_]u8{}; // dummy init
    var second_last: []const u8 = &[_]u8{};

    while (segments.next()) |seg| {
        second_last = last;
        last = seg;
    }
    return second_last;
}

/// Print all installed Artifact versions
/// Marks the version currently in use
pub fn listVersions(self: *ArtifactLister, artifact_type: Structs.Extras.ArtifactType) Errors.Artifact!void {
    self.ctx.logger.infof("Listing {s}", .{if (artifact_type == .zig) "zig" else "zep"}, @src());

    self.ctx.printer.append("Available Artifact Versions:\n", .{}, .{});

    const versions_directory = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "d",
    });
    defer self.ctx.allocator.free(versions_directory);

    if (!Fs.existsDir(versions_directory)) {
        self.ctx.printer.append("No versions installed!\n\n", .{}, .{});
        return;
    }

    const manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Artifact,
        if (artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
    ) catch return Errors.Artifact.ManifestFailed;
    defer manifest.deinit();
    if (manifest.value.path.len == 0) return Errors.Artifact.ManifestFailed;

    var dir = Fs.openDir(versions_directory) catch return Errors.Artifact.FileFailed;
    defer dir.close();
    var it = dir.iterate();

    while (it.next() catch return Errors.Artifact.IterFailed) |entry| {
        if (entry.kind != .directory) continue;

        const version_name = try self.ctx.allocator.dupe(u8, entry.name);
        const version_path = try std.fs.path.join(self.ctx.allocator, &.{ versions_directory, version_name });
        defer self.ctx.allocator.free(version_path);

        var version_directory = Fs.openDir(version_path) catch return Errors.Artifact.DirFailed;
        defer version_directory.close();

        const in_use_version = std.mem.eql(
            u8,
            self.extractVersionNameFromPath(manifest.value.path),
            version_name,
        );
        self.ctx.printer.append("{s}{s}\n", .{ version_name, if (in_use_version) " (in-use)" else "" }, .{});

        var version_iterator = version_directory.iterate();
        var found_targets: bool = false;

        while (version_iterator.next() catch return Errors.Artifact.IterFailed) |version_entry| {
            found_targets = true;
            const target_name = try self.ctx.allocator.dupe(u8, version_entry.name);
            const in_use_target = std.mem.containsAtLeast(u8, manifest.value.path, 1, target_name);
            self.ctx.printer.append(" > {s}{s}\n", .{ target_name, if (in_use_version and in_use_target) " (in-use)" else "" }, .{});
        }

        if (!found_targets) {
            self.ctx.printer.append("  NO TARGETS AVAILABLE\n", .{}, .{ .color = .red });
        }
    }

    self.ctx.printer.append("\n", .{}, .{});
}
