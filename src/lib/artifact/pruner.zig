const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

/// Lists installed Artifact versions
pub const ArtifactPruner = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) !ArtifactPruner {
        return ArtifactPruner{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(_: *ArtifactPruner) void {
        // currently no deinit required
    }

    /// Prunes all Artifact versions
    /// With zero targets
    pub fn pruneVersions(self: *ArtifactPruner, artifact_type: Structs.Extras.ArtifactType) !void {
        const versions_directory = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root,
            "d",
        });
        defer self.allocator.free(versions_directory);

        if (!Fs.existsDir(versions_directory)) {
            try self.printer.append("No versions installed!\n\n", .{}, .{});
            return;
        }

        const manifest = try Manifest.readManifest(
            Structs.Manifests.ArtifactManifest,
            self.allocator,
            if (artifact_type == .zig) self.paths.zig_manifest else self.paths.zep_manifest,
        );
        defer manifest.deinit();
        if (manifest.value.path.len == 0) {
            if (artifact_type == .zep) {
                std.debug.print("\nManifest path is not defined! Use\n $ zep zep switch <zep-version>\nTo fix!\n", .{});
            } else {
                std.debug.print("\nManifest path is not defined! Use\n $ zep zig switch <zig-version>\nTo fix!\n", .{});
            }
            return error.ManifestNotFound;
        }

        var dir = try Fs.openDir(versions_directory);
        defer dir.close();
        var it = dir.iterate();

        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            const version_path = try std.fs.path.join(self.allocator, &.{ versions_directory, entry.name });
            defer self.allocator.free(version_path);

            var version_directory = try Fs.openDir(version_path);
            defer version_directory.close();

            var version_iterator = version_directory.iterate();
            var has_targets: bool = false;
            while (try version_iterator.next()) |_| {
                has_targets = true;
                break;
            }

            if (!has_targets) {
                try Fs.deleteTreeIfExists(version_path);
            }
        }

        try self.printer.append("Done.\n", .{}, .{});
    }
};
