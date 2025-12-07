const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

/// Lists installed Artifact versions
pub const ArtifactLister = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ArtifactLister
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !ArtifactLister {
        return ArtifactLister{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ArtifactLister
    // ------------------------
    pub fn deinit(_: *ArtifactLister) void {
        // currently no deinit required
    }

    // ------------------------
    // Print all installed Artifact versions
    // Marks the version currently in use
    // ------------------------
    pub fn listVersions(self: *ArtifactLister, artifact_type: Structs.Extras.ArtifactType) !void {
        try self.printer.append("\nAvailable Artifact Versions:\n", .{}, .{});
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const versions_directory = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) paths.zig_root else paths.zep_root,
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
            if (artifact_type == .zig) paths.zig_manifest else paths.zep_manifest,
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

            const version_name = try self.allocator.dupe(u8, entry.name);
            const version_path = try std.fs.path.join(self.allocator, &.{ versions_directory, version_name });
            defer self.allocator.free(version_path);

            var version_directory = try Fs.openDir(version_path);
            defer version_directory.close();

            const in_use_version = std.mem.containsAtLeast(u8, manifest.value.path, 1, version_name);
            try self.printer.append("{s}{s}\n", .{ version_name, if (in_use_version) " (in-use)" else "" }, .{});

            var version_iterator = version_directory.iterate();
            var has_targets: bool = false;

            while (try version_iterator.next()) |version_entry| {
                has_targets = true;
                const target_name = try self.allocator.dupe(u8, version_entry.name);
                const in_use_target = std.mem.containsAtLeast(u8, manifest.value.path, 1, target_name);
                try self.printer.append("  > {s}{s}\n", .{ target_name, if (in_use_version and in_use_target) " (in-use)" else "" }, .{});
            }

            if (!has_targets) {
                try self.printer.append("  NO TARGETS AVAILABLE\n", .{}, .{ .color = 31 });
            }
        }

        try self.printer.append("\n", .{}, .{});
    }
};
