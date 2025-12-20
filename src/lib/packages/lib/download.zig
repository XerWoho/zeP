const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Package = @import("core").Package;

const Cacher = @import("cache.zig").Cacher;

const TEMPORARY_DIRECTORY_PATH = ".zep/.ZEPtmp";

pub const Downloader = struct {
    allocator: std.mem.Allocator,
    cacher: Cacher,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        cacher: Cacher,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) !Downloader {
        return Downloader{
            .allocator = allocator,
            .cacher = cacher,
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(_: *Downloader) void {}

    fn fetchPackage(
        self: *Downloader,
        package_id: []const u8,
        url: []const u8,
    ) !void {
        // allocate paths and free them after use
        const path = try std.fs.path.join(
            self.allocator,
            &.{ self.paths.pkg_root, package_id },
        );
        defer self.allocator.free(path);
        if (Fs.existsDir(path)) try Fs.deleteTreeIfExists(path);

        // create/open temporary directory
        var temporary_directory = try Fs.openOrCreateDir(TEMPORARY_DIRECTORY_PATH);
        defer temporary_directory.close();
        defer {
            Fs.deleteTreeIfExists(TEMPORARY_DIRECTORY_PATH) catch {
                self.printer.append("\nFailed to delete temp directory!\n", .{}, .{ .color = .red }) catch {};
            };
        }

        try self.printer.append("Installing package... [{s}]\n", .{url}, .{});

        const uri = try std.Uri.parse(url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var body = std.Io.Writer.Allocating.init(self.allocator);
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
        const temp_path = ".zep/.ZEPtmp/tmp.zip";

        blk: {
            var temp_file = try Fs.openFile(temp_path);
            defer temp_file.close();
            _ = try temp_file.write(data);
            break :blk;
        }

        var temp_file = try Fs.openFile(temp_path);
        defer temp_file.close();
        var reader_buf: [Constants.Default.kb * 16]u8 = undefined;
        var reader = temp_file.reader(&reader_buf);

        try self.printer.append("Extracting...\n", .{}, .{});
        var diagnostics = std.zip.Diagnostics{
            .allocator = self.allocator,
        };

        defer diagnostics.deinit();
        try std.zip.extract(temporary_directory, &reader, .{ .diagnostics = &diagnostics });

        // build path for the extracted top-level component and rename to final path
        try self.printer.append("Writing...\n", .{}, .{});
        var buf: [256]u8 = undefined;
        const extract_target = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}",
            .{
                TEMPORARY_DIRECTORY_PATH,
                diagnostics.root_dir,
            },
        );

        try std.fs.cwd().rename(extract_target, path);
        try self.filterPackage(path);
    }

    fn filterPackage(self: *Downloader, path: []const u8) !void {
        // LEGACY
        // ---
        // Might not be required anymore, as the packages are now being copied over
        // via the source code (instead of git-cloning)
        //
        if (builtin.os.tag == .windows) {
            const dot_git_pattern = try std.fmt.allocPrint(self.allocator, "{s}/.git/objects/pack/*", .{path});
            defer self.allocator.free(dot_git_pattern);

            var rm_child = std.process.Child.init(&.{ "attrib", "-R", dot_git_pattern, "/S", "/D" }, self.allocator);
            rm_child.stdin_behavior = .Ignore;
            rm_child.stdout_behavior = .Ignore;
            rm_child.stderr_behavior = .Ignore;
            _ = rm_child.spawnAndWait() catch {
                try self.printer.append("warning: attrib failed\n", .{}, .{});
            };
        }

        try self.printer.append("Filtering unimportant folders...\n\n", .{}, .{});
        for (Constants.Extras.filtering.folders) |folder| {
            var buf: [256]u8 = undefined;
            const folder_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ path, folder });
            try Fs.deleteTreeIfExists(folder_path);
        }
        for (Constants.Extras.filtering.files) |file| {
            var buf: [256]u8 = undefined;
            const file_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ path, file });
            try Fs.deleteFileIfExists(file_path);
        }
    }

    fn doesPackageExist(
        self: *Downloader,
        package_id: []const u8,
    ) !bool {
        const path = try std.fs.path.join(
            self.allocator,
            &.{ self.paths.pkg_root, package_id },
        );
        defer self.allocator.free(path);

        return Fs.existsDir(path);
    }

    pub fn downloadPackage(
        self: *Downloader,
        package_id: []const u8,
        url: []const u8,
    ) !void {
        const exists = try self.doesPackageExist(package_id);
        if (exists) {
            try self.printer.append(" > PACKAGE ALREADY EXISTS!\n", .{}, .{});
            return;
        }

        try self.printer.append(" > CHECKING CACHE...\n", .{}, .{});

        const is_cached = try self.cacher.isPackageCached(package_id);
        if (is_cached) {
            try self.printer.append(" > CACHE HIT!", .{}, .{});
            const get_cache = try self.cacher.getPackageFromCache(package_id);
            if (get_cache) {
                try self.printer.append(" > EXTRACTED!\n\n", .{}, .{ .color = .green });
            } else {
                try self.printer.append(" > FAILED!\n\n", .{}, .{ .color = .red });
            }
            return;
        } else {
            try self.printer.append(" > CACHE MISS!\n\n", .{}, .{});
            try self.fetchPackage(package_id, url);
        }

        try self.printer.append("Caching Package now...\n", .{}, .{});
        if (try self.cacher.setPackageToCache(package_id)) {
            try self.printer.append(" > CACHED\n", .{}, .{ .color = .green });
        } else {
            try self.printer.append(" ! FAILED\n", .{}, .{ .color = .red });
        }
    }
};
