const std = @import("std");
const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest.Manifest;
const Json = @import("core").Json.Json;

/// Handles switching between installed Artifact versions
pub const ArtifactSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
    manifest: *Manifest,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
        manifest: *Manifest,
    ) ArtifactSwitcher {
        return ArtifactSwitcher{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
            .manifest = manifest,
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
    ) !void {
        // Update manifest with new version
        try self.printer.append("Modifying Manifest...\n", .{}, .{
            .verbosity = 2,
        });
        const path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root,
            "d",
            version,
            target,
        });

        defer self.allocator.free(path);

        self.manifest.writeManifest(
            Structs.Manifests.ArtifactManifest,
            if (artifact_type == .zig) self.paths.zig_manifest else self.paths.zep_manifest,
            Structs.Manifests.ArtifactManifest{ .name = name, .path = path },
        ) catch {
            return error.ManifestUpdateFailed;
        };

        // Update zep.json and zep.lock
        blk: {
            if (artifact_type == .zep) break :blk;

            // all need to match for it to be in a zep project
            if (!Fs.existsFile(Constants.Extras.package_files.lock) or
                !Fs.existsFile(Constants.Extras.package_files.manifest) or
                !Fs.existsDir(Constants.Extras.package_files.zep_folder)) break :blk;

            var manifest = try self.manifest.readManifest(
                Structs.ZepFiles.PackageJsonStruct,
                Constants.Extras.package_files.manifest,
            );
            defer manifest.deinit();
            var lock = try self.manifest.readManifest(
                Structs.ZepFiles.PackageLockStruct,
                Constants.Extras.package_files.lock,
            );
            defer lock.deinit();

            manifest.value.zig_version = version;
            lock.value.root = manifest.value;
            self.manifest.writeManifest(
                Structs.ZepFiles.PackageJsonStruct,
                Constants.Extras.package_files.manifest,
                manifest.value,
            ) catch {
                return error.JsonUpdateFailed;
            };
            self.manifest.writeManifest(
                Structs.ZepFiles.PackageLockStruct,
                Constants.Extras.package_files.lock,
                lock.value,
            ) catch {
                return error.LockUpdateFailed;
            };
            break :blk;
        }

        try self.printer.append("Manifests up to date!\n", .{}, .{});

        // Update system PATH to point to new version
        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink(artifact_type, self.paths, self.manifest) catch {
            return error.LinkUpdateFailed;
        };

        try self.printer.append("Switched to installed version successfully!\n", .{}, .{ .color = .green });
    }

    /// Switch active Artifact version
    /// Updates manifest and system PATH
    pub fn getLatestVersion(self: *ArtifactSwitcher, artifact_type: Structs.Extras.ArtifactType, skip_version: []const u8) !LatestArtifact {
        // Update manifest with new version
        const artifact_root_path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig)
                self.paths.zig_root
            else
                self.paths.zep_root,
            "d",
        });
        defer self.allocator.free(artifact_root_path);

        const open_artifact = try Fs.openDir(artifact_root_path);
        var open_artifact_iter = open_artifact.iterate();

        var open_artifact_version: std.fs.Dir.Entry = undefined;
        while (true) {
            open_artifact_version = try open_artifact_iter.next() orelse
                return error.NoVersions;

            if (!std.mem.eql(u8, open_artifact_version.name, skip_version))
                break;
        }

        const version_name = try self.allocator.dupe(u8, open_artifact_version.name);
        const entry_version = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig)
                self.paths.zig_root
            else
                self.paths.zep_root,
            "d",
            version_name,
        });
        defer self.allocator.free(entry_version);

        var open_version = try Fs.openDir(entry_version);
        defer open_version.close();

        var open_entry = open_version.iterate();
        const target_entry = try open_entry.next() orelse return error.NoTarget;
        const target_name = try self.allocator.dupe(u8, target_entry.name);

        return LatestArtifact{ .version_name = version_name, .target_name = target_name };
    }
};

const LatestArtifact = struct {
    version_name: []const u8,
    target_name: []const u8,
};
