const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Prompt = @import("cli").Prompt;

pub const Cache = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    /// Initializes Cache
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) !Cache {
        return Cache{
            .allocator = allocator,
            .printer = printer,
            .paths = paths,
        };
    }

    pub fn deinit(_: *Cache) void {}

    pub fn list(self: *Cache) !void {
        const zepped_path = self.paths.zepped;

        var opened_zepped = try Fs.openOrCreateDir(zepped_path);
        defer opened_zepped.close();

        var opened_zepped_iter = opened_zepped.iterate();

        try self.printer.append("\nListing cached items:\n", .{}, .{});
        while (try opened_zepped_iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".zep")) {
                const path = try std.fs.path.join(self.allocator, &.{ zepped_path, entry.name });
                defer self.allocator.free(path);

                try self.printer.append("{s} is outdated, removing.\n", .{entry.name}, .{});
                try Fs.deleteFileIfExists(path);
                continue;
            }
            try self.printer.append(" - {s}\n", .{entry.name}, .{});
        }
        try self.printer.append("\n", .{}, .{});
    }

    fn cleanSingle(self: *Cache, name: []const u8) !void {
        const zepped_path = self.paths.zepped;

        var opened_zepped = try Fs.openOrCreateDir(zepped_path);
        defer opened_zepped.close();

        var opened_zepped_iter = opened_zepped.iterate();

        try self.printer.append("\nCleaning cache with target [{s}]:\n", .{name}, .{});
        var split = std.mem.splitAny(u8, name, "@");

        const package_name = split.first();
        const package_version = split.next();

        var data_found: u16 = 0;
        var failed_deletion: u16 = 0;
        while (try opened_zepped_iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".zep")) {
                const path = try std.fs.path.join(self.allocator, &.{ zepped_path, entry.name });
                defer self.allocator.free(path);

                try self.printer.append("{s} is outdated, removing.\n", .{entry.name}, .{});
                continue;
            }

            if (package_version != null) {
                const entry_name = try std.mem.replaceOwned(
                    u8,
                    self.allocator,
                    entry.name,
                    ".tar.zstd",
                    "",
                );
                defer self.allocator.free(entry_name);
                if (!std.mem.eql(u8, entry_name, name)) continue;
            } else {
                var entry_split = std.mem.splitAny(u8, entry.name, "@");
                const pkg_name = entry_split.first();
                if (!std.mem.startsWith(u8, pkg_name, package_name)) continue;
            }

            try self.printer.append(" - {s} ", .{entry.name}, .{});

            const path = try std.fs.path.join(self.allocator, &.{ zepped_path, entry.name });
            defer self.allocator.free(path);

            Fs.deleteFileIfExists(path) catch {
                failed_deletion += 1;
                try self.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
                continue;
            };
            data_found += 1;
            try self.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
        }
        if (data_found == 0) {
            try self.printer.append("No cached pacakges found.\n", .{}, .{});
            return;
        }
        try self.printer.append("\nRemoved: {d} cached packages ({d} failed)\n", .{ data_found, failed_deletion }, .{});
        try self.printer.append("Done.\n", .{}, .{});
    }

    pub fn clean(self: *Cache, name: ?[]const u8) !void {
        if (name) |n| {
            try self.cleanSingle(n);
            return;
        }

        const zepped_path = self.paths.zepped;

        var opened_zepped = try Fs.openOrCreateDir(zepped_path);
        defer opened_zepped.close();

        var opened_zepped_iter = opened_zepped.iterate();

        var stdin_buf: [100]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        try self.printer.append("\nCleaning cache:\n", .{}, .{});

        const UNITS = [5][]const u8{ "B", "KB", "MB", "GB", "TB" };
        var unit_depth: u8 = 0;
        var cache_size = try self.getSize();
        while (cache_size > 1024 * 2) {
            unit_depth += 1;
            cache_size = cache_size / 1024;
            if (unit_depth == 4) break;
        }

        if (cache_size == 0) {
            try self.printer.append("Cache is already empty.\n", .{}, .{});
            try self.printer.append("Done.\n", .{}, .{});
            return;
        }

        const prompt = try std.fmt.allocPrint(self.allocator, "This will remove all cached packages ({d} {s}). Continue? [y/N]", .{ cache_size, UNITS[unit_depth] });
        defer self.allocator.free(prompt);

        const input = try Prompt.input(self.allocator, self.printer, stdin, prompt, .{});
        defer self.allocator.free(input);
        if (input.len == 0) return;
        if (!std.mem.startsWith(u8, input, "y") and !std.mem.startsWith(u8, input, "Y")) return;

        var data_found: u16 = 0;
        var failed_deletion: u16 = 0;
        while (try opened_zepped_iter.next()) |entry| {
            try self.printer.append(" - {s} ", .{entry.name}, .{});

            const path = try std.fs.path.join(self.allocator, &.{ zepped_path, entry.name });
            defer self.allocator.free(path);

            Fs.deleteFileIfExists(path) catch {
                try self.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
                failed_deletion += 1;
                continue;
            };

            data_found += 1;
            try self.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
        }
        if (data_found == 0) {
            try self.printer.append("No cached packages found.\n", .{}, .{});
            return;
        }
        try self.printer.append("\nRemoved: {d} cached packages ({d} failed)\n", .{ data_found, failed_deletion }, .{});
        try self.printer.append("Done.\n", .{}, .{});
    }

    fn getSize(self: *Cache) !u64 {
        const zepped_path = self.paths.zepped;

        var opened_zepped = try Fs.openOrCreateDir(zepped_path);
        defer opened_zepped.close();

        var opened_zepped_iter = opened_zepped.iterate();

        var cache_size: u64 = 0;
        while (try opened_zepped_iter.next()) |entry| {
            const path = try std.fs.path.join(self.allocator, &.{ zepped_path, entry.name });
            defer self.allocator.free(path);

            var zepped_file = try Fs.openFile(path);
            defer zepped_file.close();

            const stat = try zepped_file.stat();
            cache_size += stat.size;
        }

        return cache_size;
    }

    pub fn size(self: *Cache) !void {
        try self.printer.append("\nGetting cache size...\n", .{}, .{});
        const cache_size = try self.getSize();
        try self.printer.append("Size:\n{d} Bytes\n{d} KB\n{d} MB\n\n", .{ cache_size, cache_size / 1024, cache_size / 1024 / 1024 }, .{});
    }
};
