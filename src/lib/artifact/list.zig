const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;

const Context = @import("context").Context;

/// Lists installed Artifact versions
pub const ArtifactLister = struct {
    ctx: *Context,

    pub fn init(ctx: *Context) ArtifactLister {
        return ArtifactLister{
            .ctx = ctx,
        };
    }

    pub fn deinit(_: *ArtifactLister) void {
        // currently no deinit required
    }

    fn getVersionFromPath(_: *ArtifactLister, path: []const u8) []const u8 {
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
    pub fn listVersions(self: *ArtifactLister, artifact_type: Structs.Extras.ArtifactType) !void {
        try self.ctx.printer.append("\nAvailable Artifact Versions:\n", .{}, .{});

        const versions_directory = try std.fs.path.join(self.ctx.allocator, &.{
            if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
            "d",
        });
        defer self.ctx.allocator.free(versions_directory);

        if (!Fs.existsDir(versions_directory)) {
            try self.ctx.printer.append("No versions installed!\n\n", .{}, .{});
            return;
        }

        const manifest = try self.ctx.manifest.readManifest(
            Structs.Manifests.ArtifactManifest,
            if (artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
        );
        defer manifest.deinit();
        if (manifest.value.path.len == 0) return error.ManifestNotFound;

        var dir = try Fs.openDir(versions_directory);
        defer dir.close();
        var it = dir.iterate();

        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;

            const version_name = try self.ctx.allocator.dupe(u8, entry.name);
            const version_path = try std.fs.path.join(self.ctx.allocator, &.{ versions_directory, version_name });
            defer self.ctx.allocator.free(version_path);

            var version_directory = try Fs.openDir(version_path);
            defer version_directory.close();

            const in_use_version = std.mem.eql(u8, self.getVersionFromPath(manifest.value.path), version_name);
            try self.ctx.printer.append("{s}{s}\n", .{ version_name, if (in_use_version) " (in-use)" else "" }, .{});

            var version_iterator = version_directory.iterate();
            var has_targets: bool = false;

            while (try version_iterator.next()) |version_entry| {
                has_targets = true;
                const target_name = try self.ctx.allocator.dupe(u8, version_entry.name);
                const in_use_target = std.mem.containsAtLeast(u8, manifest.value.path, 1, target_name);
                try self.ctx.printer.append("  > {s}{s}\n", .{ target_name, if (in_use_version and in_use_target) " (in-use)" else "" }, .{});
            }

            if (!has_targets) {
                try self.ctx.printer.append("  NO TARGETS AVAILABLE\n", .{}, .{ .color = .red });
            }
        }

        try self.ctx.printer.append("\n", .{}, .{});
    }
};
