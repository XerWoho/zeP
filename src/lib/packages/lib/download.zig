const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Package = @import("core").Package;

const Cacher = @import("cache.zig").Cacher;

const EXTRACT_DIRECTORY_PATH = ".zep/.ZEPtmp";

const Projects = @import("../../cloud/project.zig").Project;
const Context = @import("context").Context;

pub const Downloader = struct {
    ctx: *Context,
    cacher: Cacher,

    pub fn init(
        ctx: *Context,
    ) Downloader {
        const cacher = Cacher.init(ctx);

        return .{
            .ctx = ctx,
            .cacher = cacher,
        };
    }

    pub fn deinit(_: *Downloader) void {}

    const ArchiveType = enum {
        zip,
        tar_zstd,
    };

    fn downloadAndExtract(
        self: *Downloader,
        url: []const u8,
        archive_type: ArchiveType,
        out_path: []const u8,
    ) !void {
        const uri = try std.Uri.parse(url);
        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();

        const extract_path = switch (archive_type) {
            .zip => ".zep/.ZEPtmp/tmp.zip",
            .tar_zstd => ".zep/.ZEPtmp/tmp.tar.zstd",
        };

        var file = try Fs.openFile(extract_path);
        defer file.close();

        var writer_buf: [Constants.Default.kb]u8 = undefined;
        var writer = file.writer(&writer_buf);
        const fetched = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &writer.interface,
        });

        if (fetched.status == .not_found)
            return error.NotFound;

        try self.ctx.printer.append("Extracting...\n", .{}, .{});
        if (archive_type == .zip) {
            try self.extractZip(extract_path, out_path);
        } else {
            try self.ctx.compressor.decompress(extract_path, out_path);
        }
    }

    fn resolveCloudUrl(
        project: *Projects,
        name: []const u8,
        version: []const u8,
    ) !?[]const u8 {
        const fetched = project.getProject(name) catch return null;
        defer fetched.project.deinit();
        defer fetched.releases.deinit();

        for (fetched.releases.value) |r| {
            if (std.mem.eql(u8, r.Release, version)) {
                return r.Url;
            }
        }
        return null;
    }

    fn extractZip(self: *Downloader, extract_path: []const u8, path: []const u8) !void {
        // create/open extract directory
        var extract_directory = try Fs.openOrCreateDir(EXTRACT_DIRECTORY_PATH);
        defer extract_directory.close();
        defer {
            Fs.deleteTreeIfExists(EXTRACT_DIRECTORY_PATH) catch {
                self.ctx.printer.append("\nFailed to delete temp directory!\n", .{}, .{ .color = .red }) catch {};
            };
        }

        var extract_file = try Fs.openFile(extract_path);
        defer extract_file.close();
        var reader_buf: [Constants.Default.kb * 16]u8 = undefined;
        var reader = extract_file.reader(&reader_buf);

        var diagnostics = std.zip.Diagnostics{
            .allocator = self.ctx.allocator,
        };

        defer diagnostics.deinit();
        try std.zip.extract(extract_directory, &reader, .{ .diagnostics = &diagnostics });

        var buf: [Constants.Default.kb]u8 = undefined;
        const extract_target = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}",
            .{
                EXTRACT_DIRECTORY_PATH,
                diagnostics.root_dir,
            },
        );

        try std.fs.cwd().rename(extract_target, path);
    }

    fn fetchPackage(
        self: *Downloader,
        package_id: []const u8,
        url: []const u8,
    ) !void {
        // allocate paths and free them after use
        const path = try std.fs.path.join(
            self.ctx.allocator,
            &.{ self.ctx.paths.pkg_root, package_id },
        );
        defer self.ctx.allocator.free(path);
        if (Fs.existsDir(path)) try Fs.deleteTreeIfExists(path);

        try self.ctx.printer.append("Fetching package... [{s}]\n", .{url}, .{});
        var project = Projects.init(self.ctx);
        var split = std.mem.splitAny(u8, package_id, "@");
        const package_name = split.first();
        const package_version = split.next() orelse "";

        if (try resolveCloudUrl(&project, package_name, package_version)) |cloud_url| {
            try self.downloadAndExtract(
                cloud_url,
                .tar_zstd,
                path,
            );
            try Fs.deleteTreeIfExists(".zep/ZEPtmp");
            return;
        }

        // fallback
        try self.downloadAndExtract(
            url,
            .zip,
            path,
        );
    }

    fn doesPackageExist(
        self: *Downloader,
        package_id: []const u8,
    ) !bool {
        const path = try std.fs.path.join(
            self.ctx.allocator,
            &.{ self.ctx.paths.pkg_root, package_id },
        );
        defer self.ctx.allocator.free(path);

        return Fs.existsDir(path);
    }

    pub fn downloadPackage(
        self: *Downloader,
        package_id: []const u8,
        url: []const u8,
    ) !void {
        try self.ctx.printer.append("Downloading Package...\n", .{}, .{});

        const exists = try self.doesPackageExist(package_id);
        if (exists) {
            try self.ctx.printer.append(" > PACKAGE ALREADY EXISTS!\n", .{}, .{});
            return;
        }

        const is_cached = try self.cacher.isPackageCached(package_id);
        if (is_cached) {
            self.cacher.getPackageFromCache(package_id) catch {
                try self.ctx.printer.append(" ! CACHE FAILED\n\n", .{}, .{ .color = .red });
            };
        } else {
            try self.ctx.printer.append(" > CACHE MISS!\n\n", .{}, .{});
            try self.fetchPackage(package_id, url);
            self.cacher.setPackageToCache(package_id) catch {
                try self.ctx.printer.append(" ! CACHING FAILED\n\n", .{}, .{ .color = .red });
            };
        }
    }
};
