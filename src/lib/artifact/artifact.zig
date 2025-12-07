const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const Manifest = @import("core").Manifest;

const ArtifactInstaller = @import("install.zig");
const ArtifactUninstaller = @import("uninstall.zig");
const ArtifactLister = @import("list.zig");
const ArtifactSwitcher = @import("switch.zig");

// ------------------------
// Version Data
// ------------------------
pub const Version = struct {
    path: []const u8,
    tarball: []const u8,
    name: []const u8,
    version: []const u8,
};

// ------------------------
// Artifact Manager
// ------------------------
pub const Artifact = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    installer: ArtifactInstaller.ArtifactInstaller,
    uninstaller: ArtifactUninstaller.ArtifactUninstaller,
    lister: ArtifactLister.ArtifactLister,
    switcher: ArtifactSwitcher.ArtifactSwitcher,

    artifact_type: Structs.Extras.ArtifactType,
    artifact_name: []const u8,

    // ------------------------
    // Initialize all submodules
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer, artifact_type: Structs.Extras.ArtifactType) !Artifact {
        const installer = try ArtifactInstaller.ArtifactInstaller.init(allocator, printer);
        const uninstaller = try ArtifactUninstaller.ArtifactUninstaller.init(allocator, printer);
        const lister = try ArtifactLister.ArtifactLister.init(allocator, printer);
        const switcher = try ArtifactSwitcher.ArtifactSwitcher.init(allocator, printer);

        return Artifact{
            .allocator = allocator,
            .printer = printer,
            .installer = installer,
            .uninstaller = uninstaller,
            .lister = lister,
            .switcher = switcher,
            .artifact_type = artifact_type,
            .artifact_name = if (artifact_type == .zig) "Zig" else "Zep",
        };
    }

    pub fn deinit(self: *Artifact) void {
        self.installer.deinit();
        self.uninstaller.deinit();
        self.switcher.deinit();
        self.lister.deinit();
    }

    // ------------------------
    // Fetch version metadata from Artifact JSON
    // ------------------------
    fn fetchVersion(self: *Artifact, target_version: []const u8) !std.json.Value {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var server_header_buffer: [Constants.Default.kb * 32]u8 = undefined;
        const uri = try std.Uri.parse(
            if (self.artifact_type == .zig)
                Constants.Default.zig_download_index
            else
                Constants.Default.zep_download_index,
        );
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &server_header_buffer });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();

        var reader = req.reader();
        const body = try reader.readAllAlloc(self.allocator, Constants.Default.mb * 50);
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        const obj = parsed.value.object;

        if (std.mem.eql(u8, target_version, "latest") or target_version.len == 0) {
            return obj.get("master") orelse return error.NotFound;
        }
        return obj.get(target_version) orelse return error.NotFound;
    }

    // ------------------------
    // Get structured version info
    // ------------------------
    pub fn getVersion(self: *Artifact, target_version: []const u8, target: []const u8) !Version {
        try self.printer.append("Getting target version...\n", .{}, .{});
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const version_data = self.fetchVersion(target_version) catch |err| {
            try self.printer.append("Version not found...\n\n", .{}, .{});
            std.debug.print("{any}\n", .{err});
            std.process.exit(0);
        };

        const obj = version_data.object;
        const url_value = obj.get(target) orelse {
            try self.printer.append("Target not found...\n\n", .{}, .{});
            return Version{ .name = "", .path = "", .tarball = "", .version = "" };
        };

        const tarball_value = url_value.object.get("tarball") orelse {
            try self.printer.append("Tarball not found...\n\n", .{}, .{});
            return Version{ .name = "", .path = "", .tarball = "", .version = "" };
        };
        const tarball = tarball_value.string;
        var resolved_version: []const u8 = target_version;
        if (obj.get("version")) |v| {
            resolved_version = v.string;
        }

        // Parse name from tarball URL
        var tarball_split = std.mem.splitBackwardsScalar(u8, tarball, '/');
        const version_name = tarball_split.first();

        const n = if (builtin.os.tag == .windows) 4 else 7; // ".zip" / ".tar.xz"
        const name = version_name[0 .. version_name.len - n];

        const path = try std.fs.path.join(
            self.allocator,
            &.{
                if (self.artifact_type == .zig) paths.zig_root else paths.zep_root,
                "d",
                resolved_version,
                target,
            },
        );

        return Version{
            .path = path,
            .name = name,
            .version = resolved_version,
            .tarball = tarball,
        };
    }

    // ------------------------
    // Install a Artifact version
    // ------------------------
    pub fn install(self: *Artifact, target_version: []const u8, target: []const u8) !void {
        try self.printer.append("Installing version: {s}\nWith target: {s}\n\n", .{ target_version, target }, .{});
        const version = try self.getVersion(target_version, target);
        if (version.path.len == 0) return;

        if (Fs.existsDir(version.path)) {
            try self.printer.append("{s} version already installed.\n", .{self.artifact_name}, .{});
            try self.printer.append("Switching to {s} - {s}.\n\n", .{ target_version, target }, .{});
            try self.switchVersion(target_version, target);
            return;
        }

        try self.installer.install(
            version.name,
            version.tarball,
            version.version,
            target,
            self.artifact_type,
        );
    }

    // ------------------------
    // Uninstall a Artifact version
    // ------------------------
    pub fn uninstall(
        self: *Artifact,
        target_version: []const u8,
        target: []const u8,
    ) !void {
        try self.printer.append("Uninstalling version: {s}\nWith target: {s}\n\n", .{ target_version, target }, .{});
        const version = try self.getVersion(target_version, target);
        if (!Fs.existsDir(version.path)) {
            try self.printer.append("{s} version is not installed.\n\n", .{self.artifact_name}, .{});
            return;
        }

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const version_dir = try std.fs.path.join(
            self.allocator,
            &.{
                if (self.artifact_type == .zig) paths.zig_root else paths.zep_root,
                "d",
                version.version,
            },
        );
        const version_opened_dir = try Fs.openDir(version_dir);
        var version_iterator = version_opened_dir.iterate();
        var version_dir_includes_folders = false;
        while (try version_iterator.next()) |_| {
            version_dir_includes_folders = true;
            break;
        }
        const manifest = try Manifest.readManifest(Structs.Manifests.ArtifactManifest, self.allocator, if (self.artifact_type == .zig) paths.zig_manifest else paths.zep_manifest);
        defer manifest.deinit();

        if (std.mem.containsAtLeast(u8, manifest.value.name, 1, version.version)) {
            const latest = try self.switcher.getLatestVersion(self.artifact_type, version.version);
            try self.switchVersion(latest.version_name, latest.target_name);
        }

        if (version_dir_includes_folders) {
            try self.uninstaller.uninstall(version.path);
        } else {
            try self.uninstaller.uninstall(version.path);
            try Fs.deleteTreeIfExists(version_dir);
        }
        return;
    }

    // ------------------------
    // Switch active Artifact version
    // ------------------------
    pub fn switchVersion(self: *Artifact, target_version: []const u8, target: []const u8) !void {
        try self.printer.append(
            "[{s}] Switching version: {s}\nWith target: {s}\n\n",
            .{
                self.artifact_name,
                target_version,
                target,
            },
            .{},
        );
        const version = try self.getVersion(target_version, target);
        if (!Fs.existsDir(version.path)) {
            try self.printer.append(
                "{s} version not installed.\n\n",
                .{
                    self.artifact_name,
                },
                .{},
            );
            return;
        }

        try self.switcher.switchVersion(version.name, version.version, target, self.artifact_type);
    }

    // ------------------------
    // List installed Artifact versions
    // ------------------------
    pub fn list(self: *Artifact) !void {
        try self.lister.listVersions(self.artifact_type);
    }
};
