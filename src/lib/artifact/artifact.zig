const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;

const ArtifactInstaller = @import("install.zig");
const ArtifactUninstaller = @import("uninstall.zig");
const ArtifactLister = @import("list.zig");
const ArtifactSwitcher = @import("switch.zig");
const ArtifactPruner = @import("pruner.zig");

pub const VersionData = struct {
    path: []const u8,
    tarball: []const u8,
    name: []const u8,
    version: []const u8,
};

const Context = @import("context").Context;

pub const Artifact = struct {
    ctx: *Context,

    installer: ArtifactInstaller.ArtifactInstaller,
    uninstaller: ArtifactUninstaller.ArtifactUninstaller,
    lister: ArtifactLister.ArtifactLister,
    switcher: ArtifactSwitcher.ArtifactSwitcher,
    pruner: ArtifactPruner.ArtifactPruner,

    artifact_type: Structs.Extras.ArtifactType,
    artifact_name: []const u8,

    pub fn init(
        ctx: *Context,
        artifact_type: Structs.Extras.ArtifactType,
    ) !Artifact {
        const installer = ArtifactInstaller.ArtifactInstaller.init(ctx);
        const uninstaller = ArtifactUninstaller.ArtifactUninstaller.init(ctx);
        const lister = ArtifactLister.ArtifactLister.init(ctx);
        const switcher = ArtifactSwitcher.ArtifactSwitcher.init(ctx);
        const pruner = ArtifactPruner.ArtifactPruner.init(ctx);

        return Artifact{
            .ctx = ctx,
            .installer = installer,
            .uninstaller = uninstaller,
            .lister = lister,
            .switcher = switcher,
            .pruner = pruner,
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

    /// Fetch version metadata from Artifact JSON
    fn fetchVersion(self: *Artifact, target_version: []const u8) !std.json.Value {
        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(
            if (self.artifact_type == .zig)
                Constants.Default.zig_download_index
            else
                Constants.Default.zep_download_index,
        );

        var body = std.Io.Writer.Allocating.init(self.ctx.allocator);
        const fetched = try client.fetch(std.http.Client.FetchOptions{
            .location = .{
                .uri = uri,
            },
            .method = .GET,
            .response_writer = &body.writer,
        });

        if (fetched.status == .not_found) {
            return error.NotFound;
        }
        const data = body.written();
        const parsed = try std.json.parseFromSlice(std.json.Value, self.ctx.allocator, data, .{});
        const obj = parsed.value.object;

        if (std.mem.eql(u8, target_version, "latest") or target_version.len == 0) {
            return obj.get("master") orelse return error.VersionNotFound;
        }
        return obj.get(target_version) orelse return error.VersionNotFound;
    }

    /// Get structured version info
    pub fn getVersion(self: *Artifact, target_version: []const u8, target: []const u8) !VersionData {
        try self.ctx.printer.append("Getting target version...\n", .{}, .{});

        const version_data = try self.fetchVersion(target_version);

        const obj = version_data.object;
        const url_value = obj.get(target) orelse {
            return error.VersionNotFound;
        };

        const tarball_value = url_value.object.get("tarball") orelse {
            return error.TarballNotFound;
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
            self.ctx.allocator,
            &.{
                if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
                "d",
                resolved_version,
                target,
            },
        );

        return VersionData{
            .path = path,
            .name = name,
            .version = resolved_version,
            .tarball = tarball,
        };
    }

    pub fn install(self: *Artifact, target_version: []const u8, target: []const u8) anyerror!void {
        if (self.artifact_type == .zep) {
            if (!std.mem.eql(u8, Constants.Default.version, target_version)) {
                try self.ctx.printer.append("Warning: {s} is below 0.8, which is incompatible with the newer versions.\n", .{target_version}, .{});
                try self.ctx.printer.append("After installing this version, you will not be able to switch to 0.8 or later versions.\n", .{}, .{});

                var stdin_buf: [128]u8 = undefined;
                var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
                const stdin = &stdin_reader.interface;

                const answer = try Prompt.input(
                    self.ctx.allocator,
                    &self.ctx.printer,
                    stdin,
                    "Continue? (y/N) ",
                    .{},
                );
                if (answer.len == 0 or
                    std.mem.startsWith(u8, answer, "n") or
                    std.mem.startsWith(u8, answer, "N"))
                {
                    try self.ctx.printer.append("\nOk.\n", .{}, .{});
                    return;
                }
            }
        }

        try self.ctx.printer.append("Installing version: {s}\nWith target: {s}\n\n", .{ target_version, target }, .{});
        const version = try self.getVersion(target_version, target);
        if (version.path.len == 0) return error.VersionHasNoPath;

        if (Fs.existsDir(version.path)) {
            try self.ctx.printer.append("{s} version already installed.\n", .{self.artifact_name}, .{});
            try self.ctx.printer.append("Switching to {s} - {s}.\n\n", .{ target_version, target }, .{});
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

    pub fn uninstall(
        self: *Artifact,
        target_version: []const u8,
        target: []const u8,
    ) !void {
        try self.ctx.printer.append("Uninstalling version: {s}\nWith target: {s}\n\n", .{ target_version, target }, .{});
        const version = try self.getVersion(target_version, target);
        if (!Fs.existsDir(version.path)) {
            try self.ctx.printer.append("{s} version is not installed.\n\n", .{self.artifact_name}, .{});
            return;
        }

        const version_dir = try std.fs.path.join(
            self.ctx.allocator,
            &.{
                if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
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
        const manifest = try self.ctx.manifest.readManifest(
            Structs.Manifests.ArtifactManifest,
            if (self.artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
        );
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

    pub fn switchVersion(self: *Artifact, target_version: []const u8, target: []const u8) anyerror!void {
        if (self.artifact_type == .zep) {
            if (!std.mem.eql(u8, Constants.Default.version, target_version)) {
                try self.ctx.printer.append("Warning: {s} is below 0.8, which is incompatible with the newer versions.\n", .{target_version}, .{});
                try self.ctx.printer.append("After switching to this version, you will not be able to switch to 0.8 or later versions.\n", .{}, .{});

                var stdin_buf: [128]u8 = undefined;
                var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
                const stdin = &stdin_reader.interface;

                const answer = try Prompt.input(
                    self.ctx.allocator,
                    &self.ctx.printer,
                    stdin,
                    "Continue? (y/N) ",
                    .{},
                );
                if (answer.len == 0 or
                    std.mem.startsWith(u8, answer, "n") or
                    std.mem.startsWith(u8, answer, "N"))
                {
                    try self.ctx.printer.append("\nOk.\n", .{}, .{});
                    return;
                }
            }
        }

        try self.ctx.printer.append(
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
            return error.VersionNotInstalled;
        }

        try self.switcher.switchVersion(version.name, version.version, target, self.artifact_type);
    }

    pub fn list(self: *Artifact) !void {
        try self.lister.listVersions(self.artifact_type);
    }

    pub fn prune(self: *Artifact) !void {
        try self.pruner.pruneVersions(self.artifact_type);
    }
};
