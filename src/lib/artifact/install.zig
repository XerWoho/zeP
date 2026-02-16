const std = @import("std");
const builtin = @import("builtin");

pub const ArtifactInstaller = @This();

const Link = @import("lib/link.zig");

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;

const Context = @import("context");

/// Installer for Artifact versions
ctx: *Context,

pub fn init(ctx: *Context) ArtifactInstaller {
    return ArtifactInstaller{
        .ctx = ctx,
    };
}

pub fn deinit(_: *ArtifactInstaller) void {
    // currently no deinit required
}

fn download(
    self: *ArtifactInstaller,
    name: []const u8,
    tarball: []const u8,
    version: []const u8,
    target: []const u8,
    artifact_type: Structs.Extras.ArtifactType,
) !void {
    self.ctx.logger.infof("Fetching {s}", .{tarball}, @src());

    var tarball_split_iter = std.mem.splitAny(u8, tarball, ".");
    var tarball_extension = tarball_split_iter.next();
    while (tarball_split_iter.next()) |e| {
        tarball_extension = e;
    }

    const target_extension = tarball_extension orelse if (builtin.os.tag == .windows) "zip" else "tar.xz";
    const cached_file = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}.{s}",
        .{ name, target_extension },
    );
    defer self.ctx.allocator.free(cached_file);

    const target_path = try std.fs.path.join(
        self.ctx.allocator,
        &.{
            if (artifact_type == .zig)
                self.ctx.paths.zig_root
            else
                self.ctx.paths.zep_root,
            "z",
            version,
            cached_file,
        },
    );
    defer self.ctx.allocator.free(target_path);

    // Download if not cached
    if (!Fs.existsFile(target_path)) {
        var timer = try std.time.Timer.start();
        try self.fetch(tarball, target_path);
        const read = timer.read();
        const time = read / std.time.ns_per_s;
        self.ctx.printer.append("Took {d} seconds to download file.\n\n", .{time}, .{
            .color = .bright_black,
            .verbosity = 2,
        });
    } else {
        self.ctx.printer.append("Data found in cache!\n\n", .{}, .{
            .verbosity = 2,
        });
    }
    self.ctx.printer.append("Decompressing...\n", .{}, .{
        .verbosity = 2,
    });

    // Open the downloaded file
    var compressed_file = try Fs.openOrCreateFile(target_path);
    defer compressed_file.close();

    self.ctx.logger.infof("Extracting compressed data from {s}...", .{tarball}, @src());
    self.ctx.printer.append("Extracting data...\n", .{}, .{
        .verbosity = 2,
    });

    const decompressed_directory = try std.fs.path.join(
        self.ctx.allocator,
        &.{ if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root, "d", version },
    );
    _ = try Fs.openOrCreateDir(decompressed_directory);

    const main_temporary_directory = try std.fs.path.join(
        self.ctx.allocator,
        &.{ if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root, "temp" },
    );
    _ = try Fs.openOrCreateDir(main_temporary_directory);

    const temporary_directory = try std.fs.path.join(
        self.ctx.allocator,
        &.{ if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root, "temp", version },
    );

    defer {
        Fs.deleteTreeIfExists(main_temporary_directory) catch {};
        self.ctx.allocator.free(decompressed_directory);
    }

    var compressed_file_buf: [Constants.Default.kb * 32]u8 = undefined;
    var reader = compressed_file.reader(&compressed_file_buf);
    self.ctx.logger.info("Decompressing...", @src());
    if (std.mem.endsWith(u8, tarball, ".zip")) {
        self.decompressZip(
            &reader,
            decompressed_directory,
            temporary_directory,
            target,
        ) catch return Errors.Artifact.DecompressFailed;
    } else {
        self.decompressXz(
            &reader,
            decompressed_directory,
            temporary_directory,
            target,
            artifact_type,
        ) catch return Errors.Artifact.DecompressFailed;
    }
}

fn fetch(self: *ArtifactInstaller, url: []const u8, out_path: []const u8) Errors.Artifact!void {
    self.ctx.logger.infof("Downloading URL {s}.", .{url}, @src());
    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch return Errors.Artifact.InvalidUrl;
    self.ctx.printer.append("Fetching... [{s}]\n", .{url}, .{});
    var req = client.request(.GET, uri, .{}) catch return Errors.Artifact.FetchFailed;
    defer req.deinit();
    _ = req.sendBodiless() catch return Errors.Artifact.FetchFailed;

    self.ctx.logger.info("Writing body into data...", @src());
    self.ctx.printer.append("Getting Body...\n", .{}, .{ .verbosity = 2 });

    var head_buf: [Constants.Default.kb]u8 = undefined;
    const head = req.receiveHead(&head_buf) catch return Errors.Artifact.FetchFailed;

    if (head.head.status == .not_found) return Errors.Artifact.ArtifactNotFound;

    const content_length = head.head.content_length orelse 0;
    var transfer_buffer: [Constants.Default.kb * 16]u8 = undefined;
    const reader = req.reader.bodyReader(
        &transfer_buffer,
        head.head.transfer_encoding,
        head.head.content_length,
    );

    var out_file = Fs.openOrCreateFile(out_path) catch return Errors.Artifact.FileFailed;
    defer out_file.close();

    var buf: [Constants.Default.kb * 16]u8 = undefined;
    var downloaded: usize = 0;

    while (true) {
        if (downloaded == content_length) break;
        if (downloaded > 0) {
            self.ctx.printer.pop(1);
        }

        const n = reader.readSliceShort(&buf) catch return Errors.Artifact.FileFailed;
        if (n == 0) break;
        out_file.writeAll(buf[0..n]) catch return Errors.Artifact.FileFailed;
        downloaded += n;

        if (content_length != 0) {
            const pct = @min(100, @divTrunc(downloaded * 100, content_length));
            self.ctx.printer.append(
                "\rDownloading: {d}% ({d} / {d} KB)",
                .{ pct, downloaded / 1024, content_length / 1024 },
                .{},
            );
        } else {
            self.ctx.printer.append(
                "\rDownloading: {d} KB",
                .{downloaded / 1024},
                .{},
            );
        }
    }
    self.ctx.printer.append(
        "\n",
        .{},
        .{},
    );
    return;
}

/// Decompress for Windows (.zip)
fn decompressZip(
    self: *ArtifactInstaller,
    reader: *std.fs.File.Reader,
    decompressed_path: []const u8,
    temporary_path: []const u8,
    target: []const u8,
) !void {
    const new_target = try std.fs.path.join(self.ctx.allocator, &.{ decompressed_path, target });
    defer self.ctx.allocator.free(new_target);

    if (Fs.existsDir(new_target)) {
        self.ctx.printer.append("Already installed!\n", .{}, .{});
        return;
    }

    var dir = try Fs.openOrCreateDir(temporary_path);
    defer dir.close();
    var diagnostics = std.zip.Diagnostics{
        .allocator = self.ctx.allocator,
    };
    defer diagnostics.deinit();

    var extracted_files_progress: usize = 0;
    blk: {
        var iter = try std.zip.Iterator.init(reader);
        var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        while (try iter.next()) |entry| {
            if (extracted_files_progress > 0) {
                self.ctx.printer.pop(1);
            }
            extracted_files_progress += 1;
            self.ctx.printer.append(
                "\rExtracting: ({d} / {d} Files)",
                .{ extracted_files_progress, iter.cd_record_count },
                .{},
            );

            try entry.extract(
                reader,
                .{ .diagnostics = &diagnostics },
                &filename_buf,
                dir,
            );
            try diagnostics.nextFilename(filename_buf[0..entry.filename_len]);
        }

        break :blk;
    }
    self.ctx.printer.append("\n", .{}, .{});

    const extract_target = try std.fs.path.join(
        self.ctx.allocator,
        &.{ temporary_path, diagnostics.root_dir },
    );
    defer self.ctx.allocator.free(extract_target);

    self.ctx.printer.append(
        "Extracted {s} => {s}!\n",
        .{ extract_target, new_target },
        .{
            .verbosity = 3,
        },
    );
    try std.fs.cwd().rename(extract_target, new_target);

    const os_name = @tagName(builtin.os.tag);
    if (!std.mem.containsAtLeast(u8, target, 1, os_name)) {
        return error.InvalidOS;
    }
}

/// Decompress for POSIX (.tar.xz)
fn decompressXz(
    self: *ArtifactInstaller,
    reader: *std.fs.File.Reader,
    decompressed_path: []const u8,
    temporary_path: []const u8,
    target: []const u8,
    artifact_type: Structs.Extras.ArtifactType,
) !void {
    var dir = try Fs.openOrCreateDir(temporary_path);
    defer dir.close();

    // ! THIS NEEDS TO BE CHANGED
    // In later zig versions this will hopefully get fixed,
    // however currently this design works, even though
    // it is a really bad eye-sore.
    const deperecated_reader = reader.file.deprecatedReader();
    var decompressed = try std.compress.xz.decompress(
        self.ctx.allocator,
        deperecated_reader,
    );
    defer decompressed.deinit();

    var buf = try std.ArrayList(u8).initCapacity(self.ctx.allocator, 100);
    defer buf.deinit(self.ctx.allocator);
    var decompressed_reader = decompressed.reader();

    var progress: usize = 0;
    while (true) {
        if (progress > 0) {
            self.ctx.printer.pop(1);
        }

        var chunk: [Constants.Default.kb * 16]u8 = undefined;
        const bytes_read = try decompressed_reader.read(chunk[0..]);
        progress += bytes_read;

        self.ctx.printer.append(
            "\rDecompressing xz: ({d} KB)",
            .{progress / 1024},
            .{},
        );

        if (bytes_read == 0) break;
        try buf.appendSlice(self.ctx.allocator, chunk[0..bytes_read]);
    }
    var r = std.Io.Reader.fixed(try buf.toOwnedSlice(self.ctx.allocator));
    self.ctx.printer.append(
        "\nDecompressed!\n",
        .{},
        .{},
    );

    const new_target = try std.fs.path.join(self.ctx.allocator, &.{ decompressed_path, target });
    defer self.ctx.allocator.free(new_target);

    if (Fs.existsDir(new_target)) {
        self.ctx.printer.append("Already installed!\n", .{}, .{});
        return;
    }

    var diagnostics = std.tar.Diagnostics{
        .allocator = self.ctx.allocator,
    };

    self.ctx.printer.append("Piping Tar to File system!\n", .{}, .{
        .verbosity = 2,
    });
    try std.tar.pipeToFileSystem(
        dir,
        &r,
        .{ .mode_mode = .ignore, .diagnostics = &diagnostics },
    );
    _ = try Fs.openOrCreateDir(new_target);

    const extract_target = try std.fs.path.join(
        self.ctx.allocator,
        &.{ temporary_path, diagnostics.root_dir },
    );
    defer self.ctx.allocator.free(extract_target);
    try std.fs.cwd().rename(extract_target, new_target);

    self.ctx.printer.append(
        "Extracted {s} => {s}!\n",
        .{ extract_target, new_target },
        .{
            .verbosity = 3,
        },
    );

    if (!std.fs.has_executable_bit) return;
    const os_name = @tagName(builtin.os.tag);
    if (!std.mem.containsAtLeast(u8, target, 1, os_name)) return error.InvalidOS;

    var artifact_target: []const u8 = "zig";
    if (artifact_type == .zep) {
        artifact_target = "zeP";
        const check_exe_path = try std.fs.path.join(self.ctx.allocator, &.{ new_target, "zeP" });
        defer self.ctx.allocator.free(check_exe_path);
        if (!Fs.existsFile(check_exe_path)) {
            artifact_target = "zep";
        }
    }

    const artifact_exe_path = try std.fs.path.join(self.ctx.allocator, &.{ new_target, artifact_target });
    defer self.ctx.allocator.free(artifact_exe_path);

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
) Errors.Artifact!void {
    self.ctx.logger.infof(
        "Installing {s}",
        .{target},
        @src(),
    );

    self.download(name, tarball, version, target, artifact_type) catch |err| {
        switch (err) {
            Errors.Artifact.FetchFailed => return Errors.Artifact.FetchFailed,
            Errors.Artifact.DecompressFailed => return Errors.Artifact.DecompressFailed,
            else => return Errors.Artifact.DownloadFailed,
        }
    };
    self.ctx.printer.append(
        "Modifying Manifest...\n",
        .{},
        .{ .verbosity = 2 },
    );

    const path = try std.fs.path.join(self.ctx.allocator, &.{
        if (artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "d",
        version,
        target,
    });
    defer self.ctx.allocator.free(path);
    self.ctx.manifest.writeManifest(
        Structs.Manifests.Artifact,
        if (artifact_type == .zig)
            self.ctx.paths.zig_manifest
        else
            self.ctx.paths.zep_manifest,
        Structs.Manifests.Artifact{
            .name = name,
            .path = path,
        },
    ) catch return Errors.Artifact.ManifestFailed;

    self.ctx.printer.append(
        "Manifest Up to Date!\n",
        .{},
        .{
            .color = .green,
            .verbosity = 2,
        },
    );

    self.ctx.printer.append(
        "Switching to installed version...\n",
        .{},
        .{
            .verbosity = 2,
        },
    );
    try Link.updateLink(artifact_type, self.ctx);
    self.ctx.printer.append(
        "Switched to installed version!\n",
        .{},
        .{
            .color = .green,
        },
    );
}

fn zipExtractCount(dest: std.fs.Dir, fr: *std.fs.File.Reader, options: std.zip.ExtractOptions) !void {
    var iter = try std.zip.Iterator.init(fr);
    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
    while (try iter.next()) |entry| {
        try entry.extract(fr, options, &filename_buf, dest);
        if (options.diagnostics) |d| {
            try d.nextFilename(filename_buf[0..entry.filename_len]);
        }
    }
}

fn stripComponents(path: []const u8, count: u32) []const u8 {
    var i: usize = 0;
    var c = count;
    while (c > 0) : (c -= 1) {
        if (std.mem.indexOfScalarPos(u8, path, i, '/')) |pos| {
            i = pos + 1;
        } else {
            i = path.len;
            break;
        }
    }
    return path[i..];
}
