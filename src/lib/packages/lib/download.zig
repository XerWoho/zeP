const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Package = @import("core").Package.Package;

const Cacher = @import("cache.zig").Cacher;

const TEMPORARY_DIRECTORY_PATH = ".zep/.ZEPtmp";

pub const Downloader = struct {
    allocator: std.mem.Allocator,
    cacher: Cacher,
    package: Package,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        package: Package,
        cacher: Cacher,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) !Downloader {
        return Downloader{
            .allocator = allocator,
            .cacher = cacher,
            .package = package,
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(_: *Downloader) void {
        // Nothing to free here (fields are owned externally).
    }

    fn packagePath(self: *Downloader) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ try self.allocator.dupe(u8, self.paths.pkg_root), self.package.id },
        );
    }

    fn fetchPackage(self: *Downloader, url: []const u8) !void {
        // allocate paths and free them after use
        const path = try self.packagePath();
        defer self.allocator.free(path);

        if (Fs.existsDir(path)) try Fs.deleteDirIfExists(path);

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

        var server_header_buffer: [Constants.Default.kb * 32 * 4]u8 = undefined;
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &server_header_buffer });
        defer req.deinit();

        try self.printer.append("Sending request...\n", .{}, .{});
        try req.send();
        try req.finish();
        try self.printer.append("Waiting for response...\n", .{}, .{});
        try req.wait();

        const reader = req.reader();
        const data = try reader.readAllAlloc(self.allocator, Constants.Default.mb * 100);
        var stream = std.io.fixedBufferStream(data);

        try self.printer.append("Extracting...\n", .{}, .{});
        var diagnostics = std.zip.Diagnostics{
            .allocator = self.allocator,
        };
        defer diagnostics.deinit();
        try std.zip.extract(temporary_directory, &stream.seekableStream(), .{ .diagnostics = &diagnostics });

        try self.printer.append("Writing...\n", .{}, .{});
        // build path for the extracted top-level component and rename to final path
        const extract_target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ TEMPORARY_DIRECTORY_PATH, diagnostics.root_dir });
        defer self.allocator.free(extract_target);

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
            const folder_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, folder });
            defer self.allocator.free(folder_path);
            try Fs.deleteTreeIfExists(folder_path);
        }
        for (Constants.Extras.filtering.files) |file| {
            const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, file });
            defer self.allocator.free(file_path);
            try Fs.deleteFileIfExists(file_path);
        }
    }

    fn doesPackageExist(self: *Downloader) !bool {
        const path = try self.packagePath();
        defer self.allocator.free(path);
        return Fs.existsDir(path);
    }

    pub fn downloadPackage(self: *Downloader, url: []const u8) !void {
        const exists = try self.doesPackageExist();
        if (exists) {
            try self.printer.append(" > PACKAGE ALREADY EXISTS!\n", .{}, .{});
            return;
        }

        try self.printer.append(" > CHECKING CACHE...\n", .{}, .{});

        const isCached = try self.cacher.isPackageCached();
        if (isCached) {
            if (try self.cacher.getPackageFromCache()) {
                try self.printer.append(" > CACHE HIT!\n\n", .{}, .{});
                return;
            }
        }

        try self.printer.append(" > CACHE MISS!\n\n", .{}, .{});
        try self.fetchPackage(url);
        if (isCached) return;

        try self.printer.append("Caching Package now...\n", .{}, .{});
        if (try self.cacher.setPackageToCache(try self.packagePath())) {
            try self.printer.append("Successfully cached!\n", .{}, .{ .color = .green });
        } else {
            try self.printer.append("Caching failed...\n", .{}, .{ .color = .red });
        }
    }
};
