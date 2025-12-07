const std = @import("std");
const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json.Json;

/// Handles switching between installed Artifact versions
pub const ArtifactSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ArtifactSwitcher
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !ArtifactSwitcher {
        return ArtifactSwitcher{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ArtifactSwitcher
    // ------------------------
    pub fn deinit(_: *ArtifactSwitcher) void {
        // currently no deinit required
    }

    // ------------------------
    // Switch active Artifact version
    // Updates manifest and system PATH
    // ------------------------
    pub fn switchVersion(
        self: *ArtifactSwitcher,
        name: []const u8,
        version: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        // Update manifest with new version
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        try self.printer.append("Modifying Manifest...\n", .{}, .{});
        const path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) paths.zig_root else paths.zep_root,
            "d",
            version,
            target,
        });

        defer self.allocator.free(path);

        Manifest.writeManifest(
            Structs.Manifests.ArtifactManifest,
            self.allocator,
            if (artifact_type == .zig) paths.zig_manifest else paths.zep_manifest,
            Structs.Manifests.ArtifactManifest{ .name = name, .path = path },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        // Update zep.json and zep.lock
        blk: {
            if (artifact_type == .zep) break :blk;

            // all need to match for it to be in a zeP project
            if (!Fs.existsFile(Constants.Extras.package_files.lock) or
                !Fs.existsFile(Constants.Extras.package_files.manifest) or
                !Fs.existsDir(Constants.Extras.package_files.zep_folder)) break :blk;

            var manifest = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
            defer manifest.deinit();
            var lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
            defer lock.deinit();

            manifest.value.zig_version = version;
            lock.value.root = manifest.value;
            Manifest.writeManifest(
                Structs.ZepFiles.PackageJsonStruct,
                self.allocator,
                Constants.Extras.package_files.manifest,
                manifest.value,
            ) catch {
                try self.printer.append("Updating Json Manifest failed!\n", .{}, .{ .color = 31 });
            };
            Manifest.writeManifest(
                Structs.ZepFiles.PackageLockStruct,
                self.allocator,
                Constants.Extras.package_files.lock,
                lock.value,
            ) catch {
                try self.printer.append("Updating Lock Manifest failed!\n", .{}, .{ .color = 31 });
            };
            break :blk;
        }

        try self.printer.append("Manifests up to date!\n", .{}, .{});

        // Update system PATH to point to new version
        try self.printer.append("Switching to installed version...\n", .{}, .{});
        Link.updateLink(artifact_type) catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Switched to installed version successfully!\n", .{}, .{ .color = 32 });
    }

    // ------------------------
    // Switch active Artifact version
    // Updates manifest and system PATH
    // ------------------------
    pub fn getLatestVersion(self: *ArtifactSwitcher, artifact_type: Structs.Extras.ArtifactType, skip_version: []const u8) !LatestArtifact {
        // Update manifest with new version
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const artifact_root_path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig)
                paths.zig_root
            else
                paths.zep_root,
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
                paths.zig_root
            else
                paths.zep_root,
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
