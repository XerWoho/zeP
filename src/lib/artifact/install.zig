const std = @import("std");
const builtin = @import("builtin");

const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest.Manifest;

/// Installer for Artifact versions
pub const ArtifactInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,
    manifest: *Manifest,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
        manifest: *Manifest,
    ) ArtifactInstaller {
        return ArtifactInstaller{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
            .manifest = manifest,
        };
    }

    pub fn deinit(_: *ArtifactInstaller) void {
        // currently no deinit required
    }

    fn fetchData(
        self: *ArtifactInstaller,
        name: []const u8,
        tarball: []const u8,
        version: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        var tarball_split_iter = std.mem.splitAny(u8, tarball, ".");
        var tarball_extension = tarball_split_iter.next();
        while (tarball_split_iter.next()) |e| {
            tarball_extension = e;
        }

        const target_extension = tarball_extension orelse if (builtin.os.tag == .windows) "zip" else "tar.xz";
        var buf: [256]u8 = undefined;
        const cached_file = try std.fmt.bufPrint(
            &buf,
            "{s}.{s}",
            .{ name, target_extension },
        );

        const target_path = try std.fs.path.join(
            self.allocator,
            &.{
                if (artifact_type == .zig)
                    self.paths.zig_root
                else
                    self.paths.zep_root,
                "z",
                version,
                cached_file,
            },
        );
        defer self.allocator.free(target_path);

        // Download if not cached
        if (!Fs.existsFile(target_path)) {
            try self.downloadFile(tarball, target_path);
        } else {
            try self.printer.append("Data found in cache!\n\n", .{}, .{});
        }

        // Open the downloaded file
        var compressed_file = try Fs.openOrCreateFile(target_path);
        defer compressed_file.close();

        try self.printer.append("Extracting data...\n", .{}, .{});

        const decompressed_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root, "d", version },
        );
        _ = try Fs.openOrCreateDir(decompressed_directory);

        const main_temporary_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root, "temp" },
        );
        _ = try Fs.openOrCreateDir(main_temporary_directory);

        const temporary_directory = try std.fs.path.join(
            self.allocator,
            &.{ if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root, "temp", version },
        );

        defer {
            Fs.deleteTreeIfExists(main_temporary_directory) catch {};
            self.allocator.free(decompressed_directory);
        }

        var compressed_file_buf: [Constants.Default.kb * 32]u8 = undefined;
        var reader = compressed_file.reader(&compressed_file_buf);
        if (builtin.os.tag == .windows) {
            try self.decompressWindows(
                &reader,
                decompressed_directory,
                temporary_directory,
                target,
            );
        } else {
            try self.decompressPosix(
                &reader,
                decompressed_directory,
                temporary_directory,
                target,
                artifact_type,
            );
        }
    }

    fn downloadFile(self: *ArtifactInstaller, raw_uri: []const u8, out_path: []const u8) !void {
        try self.printer.append("Parsing URI...\n", .{}, .{});
        const uri = try std.Uri.parse(raw_uri);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var body = std.Io.Writer.Allocating.init(self.allocator);
        try self.printer.append("Fetching... [{s}]\n", .{raw_uri}, .{});
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

        try self.printer.append("Getting Body...\n", .{}, .{ .verbosity = 2 });
        const data = body.written();

        var out_file = try Fs.openOrCreateFile(out_path);
        defer out_file.close();
        _ = try out_file.write(data);

        try self.printer.append("\n", .{}, .{});
    }

    /// Decompress for Windows (.zip)
    fn decompressWindows(
        self: *ArtifactInstaller,
        reader: *std.fs.File.Reader,
        decompressed_path: []const u8,
        temporary_path: []const u8,
        target: []const u8,
    ) !void {
        const new_target = try std.fs.path.join(self.allocator, &.{ decompressed_path, target });
        defer self.allocator.free(new_target);

        if (Fs.existsDir(new_target)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        var dir = try Fs.openOrCreateDir(temporary_path);
        defer dir.close();
        var diagnostics = std.zip.Diagnostics{
            .allocator = self.allocator,
        };
        defer diagnostics.deinit();
        try std.zip.extract(dir, reader, .{ .diagnostics = &diagnostics });

        const extract_target = try std.fs.path.join(self.allocator, &.{ temporary_path, diagnostics.root_dir });
        defer self.allocator.free(extract_target);

        try self.printer.append(
            "Extracted {s} => {s}!\n",
            .{ extract_target, new_target },
            .{
                .verbosity = 2,
            },
        );
        try std.fs.cwd().rename(extract_target, new_target);
    }

    /// Decompress for POSIX (.tar.xz)
    fn decompressPosix(
        self: *ArtifactInstaller,
        reader: *std.fs.File.Reader,
        decompressed_path: []const u8,
        temporary_path: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        var dir = try Fs.openOrCreateDir(temporary_path);
        defer dir.close();

        var decompressed = try std.compress.xz.decompress(self.allocator, reader);
        defer decompressed.deinit();
        const decompressed_reader = decompressed.reader();

        const new_target = try std.fs.path.join(self.allocator, &.{ decompressed_path, target });
        defer self.allocator.free(new_target);

        if (Fs.existsDir(new_target)) {
            try self.printer.append("Already installed!\n", .{}, .{});
            return;
        }

        var diagnostics = std.tar.Diagnostics{
            .allocator = self.allocator,
        };
        try std.tar.pipeToFileSystem(dir, decompressed_reader, .{ .mode_mode = .ignore, .diagnostics = &diagnostics });

        const extract_target = try std.fs.path.join(self.allocator, &.{ temporary_path, diagnostics.root_dir });
        defer self.allocator.free(extract_target);
        const stat_extract = try std.fs.cwd().statFile(extract_target);
        if (stat_extract.kind == .file) {
            try self.printer.append(
                "Extracted {s} => {s}!\n",
                .{ temporary_path, new_target },
                .{
                    .{
                        .verbosity = 2,
                    },
                },
            );
            try std.fs.cwd().rename(temporary_path, new_target);
        } else {
            try self.printer.append(
                "Extracted {s} => {s}!\n",
                .{ extract_target, new_target },
                .{
                    .{
                        .verbosity = 2,
                    },
                },
            );
            try std.fs.cwd().rename(extract_target, new_target);
        }

        var artifact_target: []const u8 = "zig";
        if (artifact_type == .zep) {
            artifact_target = "zeP";
            const check_exe_path = try std.fs.path.join(self.allocator, &.{ new_target, "zeP" });
            defer self.allocator.free(check_exe_path);
            if (!Fs.existsFile(check_exe_path)) {
                artifact_target = "zep";
            }
        }

        const artifact_exe_path = try std.fs.path.join(self.allocator, &.{ new_target, artifact_target });
        defer self.allocator.free(artifact_exe_path);

        const artifact_exe_file = try Fs.openFile(artifact_exe_path);
        defer artifact_exe_file.close();
        try artifact_exe_file.chmod(0o755);
    }

    pub fn install(
        self: *ArtifactInstaller,
        name: []const u8,
        tarball: []const u8,
        version: []const u8,
        target: []const u8,
        artifact_type: Structs.Extras.ArtifactType,
    ) !void {
        try self.fetchData(name, tarball, version, target, artifact_type);
        try self.printer.append("Modifying Manifest...\n", .{}, .{ .verbosity = 2 });

        const path = try std.fs.path.join(self.allocator, &.{
            if (artifact_type == .zig) self.paths.zig_root else self.paths.zep_root,
            "d",
            version,
            target,
        });
        defer self.allocator.free(path);
        self.manifest.writeManifest(
            Structs.Manifests.ArtifactManifest,
            if (artifact_type == .zig)
                self.paths.zig_manifest
            else
                self.paths.zep_manifest,
            Structs.Manifests.ArtifactManifest{
                .name = name,
                .path = path,
            },
        ) catch {
            try self.printer.append("Updating Manifest failed!\n", .{}, .{ .color = .red });
        };

        try self.printer.append("Manifest Up to Date!\n", .{}, .{
            .color = .green,
        });

        try self.printer.append("Switching to installed version...\n", .{}, .{
            .verbosity = 2,
        });
        Link.updateLink(artifact_type, self.paths, self.manifest) catch {
            try self.printer.append("Updating Link has failed!\n", .{}, .{ .color = .red });
        };
        try self.printer.append("Switched to installed version!\n", .{}, .{
            .color = .green,
        });
    }
};
