const std = @import("std");
const builtin = @import("builtin");

pub const Artifact = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;

const ArtifactInstaller = @import("install.zig");
const ArtifactUninstaller = @import("uninstall.zig");
const ArtifactLister = @import("list.zig");
const ArtifactSwitcher = @import("switch.zig");
const ArtifactPruner = @import("pruner.zig");
const ArtifactCache = @import("cache.zig");

pub const VersionData = struct {
    path: []const u8,
    tarball: []const u8,
    name: []const u8,
    version: []const u8,
};

const Context = @import("context");

ctx: *Context,

installer: ArtifactInstaller,
uninstaller: ArtifactUninstaller,
lister: ArtifactLister,
switcher: ArtifactSwitcher,
pruner: ArtifactPruner,
cacher: ArtifactCache,

artifact_type: Structs.Extras.ArtifactType,
artifact_name: []const u8,

pub fn init(
    ctx: *Context,
    artifact_type: Structs.Extras.ArtifactType,
) Artifact {
    const installer = ArtifactInstaller.init(ctx);
    const uninstaller = ArtifactUninstaller.init(ctx);
    const lister = ArtifactLister.init(ctx);
    const switcher = ArtifactSwitcher.init(ctx);
    const pruner = ArtifactPruner.init(ctx);
    const cacher = ArtifactCache.init(ctx, artifact_type);

    return Artifact{
        .ctx = ctx,
        .installer = installer,
        .uninstaller = uninstaller,
        .lister = lister,
        .switcher = switcher,
        .pruner = pruner,
        .cacher = cacher,
        .artifact_type = artifact_type,
        .artifact_name = if (artifact_type == .zig) "Zig" else "Zep",
    };
}

pub fn deinit(self: *Artifact) void {
    self.installer.deinit();
    self.uninstaller.deinit();
    self.switcher.deinit();
    self.lister.deinit();
    self.cacher.deinit();
}

fn extractVersionNameFromPath(_: *Artifact, path: []const u8) []const u8 {
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

/// Fetch version metadata from Artifact JSON
fn fetchVersion(self: *Artifact, target_version: []const u8) Errors.Artifact!std.json.Value {
    self.ctx.logger.infof(
        "Fetching target version {s}",
        .{target_version},
        @src(),
    );

    const url = switch (self.artifact_type) {
        .zig => Constants.Default.zig_download_index,
        .zep => Constants.Default.zep_download_index,
    };
    var parsed = self.ctx.fetcher.fetchJson(url, std.json.Value) catch return Errors.Artifact.FetchFailed;
    defer parsed.deinit();

    const obj = parsed.value.object;
    if (std.mem.eql(u8, target_version, "latest") or target_version.len == 0) {
        return obj.get("master") orelse Errors.Artifact.InvalidVersion;
    }

    return obj.get(target_version) orelse Errors.Artifact.InvalidVersion;
}

/// Get structured version info
pub fn getVersion(self: *Artifact, target_version: []const u8, target: []const u8) Errors.Artifact!VersionData {
    self.ctx.logger.infof(
        "Getting target version version={s} target={s}",
        .{ target_version, target },
        @src(),
    );
    self.ctx.printer.append(
        "Getting version {s}, with target {s}...\n",
        .{ target_version, target },
        .{
            .verbosity = 2,
        },
    );

    const version_data = try self.fetchVersion(target_version);

    const obj = version_data.object;
    const url_value = obj.get(target) orelse return Errors.Artifact.InvalidVersion;

    const tarball_value = url_value.object.get("tarball") orelse return Errors.Artifact.InvalidTarball;
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

pub fn install(self: *Artifact, target_version: []const u8, target: []const u8) Errors.Artifact!void {
    self.ctx.logger.infof(
        "Installing {s}, version={s}, target={s}",
        .{
            if (self.artifact_type == .zig) "zig" else "zep",
            target_version,
            target,
        },
        @src(),
    );

    const version = try self.getVersion(target_version, target);
    if (version.path.len == 0) return Errors.Artifact.InvalidVersion;
    if (Fs.existsDir(version.path)) return Errors.Artifact.AlreadyInstalled;

    self.ctx.printer.append(
        "[{s}] Installing version: {s}\nWith target: {s}\n\n",
        .{
            if (self.artifact_type == .zep) "Zep" else "Zig",
            target_version,
            target,
        },
        .{},
    );
    if (self.artifact_type == .zep) {
        var outdated = false;
        const v = version.version;
        if (v.len == 3) outdated = !std.mem.eql(u8, "0.8", v);

        if (outdated) {
            self.ctx.printer.append(
                "Warning: {s} is below 0.8, which is incompatible with the newer versions.\n",
                .{v},
                .{},
            );
            self.ctx.printer.append(
                "After installing this version, you will not be able to switch to 0.8 or later versions.\n",
                .{},
                .{},
            );

            const answer = Prompt.input(
                self.ctx.allocator,
                &self.ctx.printer,
                "Continue? (y/N) ",
                .{},
            ) catch return Errors.Artifact.OutOfMemory;
            if (answer.len == 0 or (!std.mem.startsWith(u8, answer, "y") and !std.mem.startsWith(u8, answer, "Y"))) {
                self.ctx.printer.append(
                    "\nOk.\n",
                    .{},
                    .{},
                );
                return;
            }
        }
    }

    try self.installer.install(
        version.name,
        version.tarball,
        version.version,
        target,
        self.artifact_type,
    );
}

pub fn uninstall(self: *Artifact, target_version: []const u8, target: []const u8) Errors.Artifact!void {
    self.ctx.logger.infof(
        "Uninstalling {s}, version={s}, target={s}",
        .{
            if (self.artifact_type == .zig) "zig" else "zep",
            target_version,
            target,
        },
        @src(),
    );

    self.ctx.printer.append(
        "[{s}] Uninstalling version: {s}\nWith target: {s}\n\n",
        .{
            if (self.artifact_type == .zep) "Zep" else "Zig",
            target_version,
            target,
        },
        .{},
    );

    const versions_dir = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
            "d",
            target_version,
        },
    );
    defer self.ctx.allocator.free(versions_dir);
    const target_dir = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            versions_dir,
            target,
        },
    );
    defer self.ctx.allocator.free(target_dir);

    const manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Artifact,
        if (self.artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
    ) catch return Errors.Artifact.ManifestFailed;
    defer manifest.deinit();

    if (std.mem.containsAtLeast(u8, manifest.value.name, 1, target_version)) {
        self.ctx.logger.info(
            "Target version is selected | Attempting switch",
            @src(),
        );
        const latest = self.switcher.getLatestVersionExcept(
            self.artifact_type,
            target_version,
        ) catch return Errors.Artifact.InvalidVersion;
        try self.switchVersion(latest.version_name, latest.target_name);
        self.ctx.logger.info(
            "Switch completed.",
            @src(),
        );
    }

    try self.uninstaller.uninstall(target_dir);
    try self.pruner.pruneVersions(self.artifact_type);
    return;
}

pub fn switchVersion(self: *Artifact, target_version: []const u8, target: []const u8) Errors.Artifact!void {
    self.ctx.logger.infof(
        "Switching {s} version",
        .{if (self.artifact_type == .zig) "zig" else "zep"},
        @src(),
    );

    const version = try self.getVersion(target_version, target);
    if (!Fs.existsDir(version.path)) return Errors.Artifact.NotInstalled;

    if (self.artifact_type == .zep) {
        var outdated = false;
        const v = version.version;
        if (v.len == 3) outdated = !std.mem.eql(u8, "0.8", v);

        if (outdated) {
            self.ctx.printer.append(
                "Warning: {s} is below 0.8, which is incompatible with the newer versions.\n",
                .{target_version},
                .{},
            );
            self.ctx.printer.append(
                "After switching to this version, you will not be able to switch to 0.8 or later versions.\n",
                .{},
                .{},
            );

            const answer = Prompt.input(
                self.ctx.allocator,
                &self.ctx.printer,
                "Continue? (y/N) ",
                .{},
            ) catch return Errors.Artifact.OutOfMemory;
            if (answer.len == 0 or
                (!std.mem.startsWith(u8, answer, "y") and
                    !std.mem.startsWith(u8, answer, "Y")))
            {
                self.ctx.printer.append(
                    "\nOk.\n",
                    .{},
                    .{},
                );
                return;
            }
        }
    }

    self.ctx.printer.append(
        "[{s}] Switching version: {s}\nWith target: {s}\n\n",
        .{
            self.artifact_name,
            target_version,
            target,
        },
        .{},
    );

    try self.switcher.switchVersion(
        version.name,
        version.version,
        target,
        self.artifact_type,
    );
}

pub fn currentVersion(self: *Artifact) Errors.Artifact![]const u8 {
    const versions_directory = try std.fs.path.join(self.ctx.allocator, &.{
        if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "d",
    });
    defer self.ctx.allocator.free(versions_directory);

    if (!Fs.existsDir(versions_directory)) {
        self.ctx.printer.append("No versions installed!\n\n", .{}, .{});
        return Errors.Artifact.InvalidVersion;
    }

    const manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Artifact,
        if (self.artifact_type == .zig) self.ctx.paths.zig_manifest else self.ctx.paths.zep_manifest,
    ) catch return Errors.Artifact.ManifestFailed;
    defer manifest.deinit();
    if (manifest.value.path.len == 0) return Errors.Artifact.ManifestFailed;

    const v = self.extractVersionNameFromPath(manifest.value.path);
    return v;
}

pub fn list(self: *Artifact) !void {
    try self.lister.listVersions(self.artifact_type);
}

pub fn listCache(self: *Artifact) Errors.Cache!void {
    try self.cacher.list();
}
pub fn cleanCache(self: *Artifact, version: ?[]const u8) Errors.Cache!void {
    if (version) |v| {
        try self.cacher.cleanOne(v);
        return;
    }

    try self.cacher.cleanAll();
}
pub fn sizeCache(self: *Artifact) Errors.Cache!void {
    try self.cacher.size();
}
