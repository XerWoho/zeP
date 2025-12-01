const std = @import("std");
const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json.Json;

/// Handles switching between installed Zig versions
pub const ZigSwitcher = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    // ------------------------
    // Initialize ZigSwitcher
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !ZigSwitcher {
        return ZigSwitcher{ .allocator = allocator, .printer = printer };
    }

    // ------------------------
    // Deinitialize ZigSwitcher
    // ------------------------
    pub fn deinit(_: *ZigSwitcher) void {
        // currently no deinit required
    }

    // ------------------------
    // Switch active Zig version
    // Updates manifest and system PATH
    // ------------------------
    pub fn switchVersion(self: *ZigSwitcher, name: []const u8, version: []const u8, target: []const u8) !void {
        // Update manifest with new version
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        try self.printer.append("Modifying Manifest...\n", .{}, .{});
        const path = try std.fs.path.join(self.allocator, &.{ paths.zig_root, "d", version, target });
        defer self.allocator.free(path);

        Manifest.writeManifest(
            Structs.Manifests.ZigManifest,
            self.allocator,
            paths.zig_manifest,
            Structs.Manifests.ZigManifest{ .name = name, .path = path },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = 31 });
        };

        // Update zep.json and zep.lock
        blk: {
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
        Link.updateLink() catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = 31 });
        };

        try self.printer.append("Switched to installed version successfully!\n", .{}, .{ .color = 32 });
    }
};
