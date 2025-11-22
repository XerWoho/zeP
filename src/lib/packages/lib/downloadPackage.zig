const std = @import("std");
const builtin = @import("builtin");

const Locales = @import("locales");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPackage = Utils.UtilsPackage;
const UtilsPrinter = Utils.UtilsPrinter;

const CachePackage = @import("cachePackage.zig");

pub const Downloader = struct {
    allocator: std.mem.Allocator,
    cacher: CachePackage.Cacher,
    package: UtilsPackage.Package,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, package: UtilsPackage.Package, cacher: CachePackage.Cacher, printer: *UtilsPrinter.Printer) !Downloader {
        return Downloader{
            .allocator = allocator,
            .cacher = cacher,
            .package = package,
            .printer = printer,
        };
    }

    pub fn deinit(_: *Downloader) void {
        // Nothing to free here (fields are owned externally).
    }

    // small helper: alloc formatted string and make caller responsible for free
    fn allocFmt(self: *Downloader, fmt: []const u8, args: anytype) ![]u8 {
        // Note: zig fmt helpers differ by version; keep this pattern.
        return std.fmt.allocPrint(self.allocator, fmt, args);
    }

    fn packagePath(self: *Downloader) ![]u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}",
            .{ Constants.ROOT_ZEP_PKG_FOLDER, self.package.packageName, self.package.packageVersion },
        );
    }

    fn tmpDirPath(_: *Downloader) []const u8 {
        // no need to alloc a constant path every time
        return ".ZEPtmp";
    }

    fn ensureTmpDir(self: *Downloader) !std.fs.Dir {
        const path = self.tmpDirPath();
        // create directory if not exists; openCDir returns Dir
        return UtilsFs.openCDir(path);
    }

    fn removeTmpDir(self: *Downloader) !void {
        // best effort cleanup
        try std.fs.cwd().deleteTree(self.tmpDirPath());
    }

    fn writeStreamToFile(self: *Downloader, reader: anytype, out_path: []const u8) !void {
        var out_file = try UtilsFs.openCFile(out_path);
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        defer {
            buffered_writer.flush() catch {
                @panic("failed to flush buffer!");
            };
        }

        var buf: [4096 * 4]u8 = undefined;
        var progress_counter: u32 = 0;
        var dot_counter: u8 = 0;

        while (true) {
            const n = try reader.read(&buf);
            if (n == 0) break;
            try buffered_writer.writer().writeAll(buf[0..n]);

            progress_counter += 1;
            if (progress_counter > 200) {
                if (dot_counter >= 3) {
                    self.printer.pop(3);
                    dot_counter = 0;
                }
                try self.printer.append(".", .{}, .{});
                dot_counter += 1;
                progress_counter = 0;
            }
        }
        try self.printer.append("\n", .{}, .{});
    }

    fn fetchPackage(self: *Downloader, url: []const u8) !void {
        // allocate paths and free them after use
        const path = try self.packagePath();
        defer self.allocator.free(path);

        if (UtilsFs.checkDirExists(path)) {
            try UtilsFs.delDir(path);
        }

        // create/open temporary directory
        var tmp_dir = try self.ensureTmpDir();
        defer tmp_dir.close();
        defer {
            self.removeTmpDir() catch {
                @panic("Failed to remove temporary directory!");
            };
        }

        try self.printer.append("Installing package... [{s}]\n", .{url}, .{});
        const uri = try std.Uri.parse(url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var server_buf: [4096 * 4]u8 = undefined;
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &server_buf });
        defer req.deinit();

        try self.printer.append("Sending request...\n", .{}, .{});
        try req.send();
        try req.finish();
        try self.printer.append("Waiting for response...\n", .{}, .{});
        try req.wait();

        const zipped_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}@{s}.zip",
            .{ Constants.ROOT_ZEP_ZEPPED_FOLDER, self.package.packageName, self.package.packageVersion },
        );
        defer {
            std.fs.cwd().deleteFile(zipped_path) catch {
                @panic("failed to delete zip file");
            };
            self.allocator.free(zipped_path);
        }

        // write HTTP body to zip file
        const reader = req.reader();
        try self.writeStreamToFile(reader, zipped_path);

        try self.printer.append("Decompressing...\n", .{}, .{});

        // Open the zip file for reading
        var read_file = try UtilsFs.openFile(zipped_path);
        defer read_file.close();

        // Attempt to iterate zip entries and extract
        var iter = try std.zip.Iterator(@TypeOf(read_file.seekableStream())).init(read_file.seekableStream());
        var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        var selected_file: []u8 = undefined;

        while (try iter.next()) |entry| {
            const crc = try entry.extract(read_file.seekableStream(), .{}, &filename_buf, tmp_dir);
            if (crc != entry.crc32) continue;
            selected_file = filename_buf[0..entry.filename_len];
            break;
        }

        try std.zip.extract(tmp_dir, read_file.seekableStream(), .{});

        // build path for the extracted top-level component and rename to final path
        const extract_target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.tmpDirPath(), selected_file });
        defer self.allocator.free(extract_target);

        try std.fs.cwd().rename(extract_target, path);

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
                _ = try self.printer.append("warning: attrib failed\n", .{}, .{});
            };
        }

        try self.printer.append("Filtering unimportant folders...\n\n", .{}, .{});
        for (Constants.FILTER_PACKAGE_FOLDERS) |folder| {
            const folder_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, folder });
            defer self.allocator.free(folder_path);
            _ = UtilsFs.delTree(folder_path) catch {};
        }
        for (Constants.FILTER_PACKAGE_FILES) |file| {
            const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, file });
            defer self.allocator.free(file_path);
            _ = UtilsFs.delFile(file_path) catch {};
        }
    }

    fn doesPackageExist(self: *Downloader) !bool {
        const path = try self.packagePath();
        defer self.allocator.free(path);
        return UtilsFs.checkDirExists(path);
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
            try self.printer.append("Successfully cached!\n", .{}, .{ .color = 32 });
        } else {
            try self.printer.append("Caching failed...\n", .{}, .{ .color = 31 });
        }
    }
};
