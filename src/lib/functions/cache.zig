const std = @import("std");
const builtin = @import("builtin");

pub const Cache = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Errors = @import("errors");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Prompt = @import("cli").Prompt;
const Context = @import("context");

ctx: *Context,

/// Initializes Cache
pub fn init(ctx: *Context) Cache {
    return Cache{
        .ctx = ctx,
    };
}

pub fn deinit(_: *Cache) void {}

pub fn list(self: *Cache) Errors.Cache!void {
    self.ctx.logger.info("Listing Cache", @src());

    self.ctx.printer.append("Packages:\n", .{}, .{});
    try self.listSingle(self.ctx.paths.pkg_cached);

    self.ctx.printer.append("Metadata:\n", .{}, .{});
    try self.listSingle(self.ctx.paths.meta_cached);
}

fn listSingle(
    self: *Cache,
    cached_path: []const u8,
) Errors.Cache!void {
    self.ctx.logger.info("Listing Cache", @src());

    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    var is_items_listed = false;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        is_items_listed = true;
        if (std.mem.endsWith(u8, entry.name, ".zep")) {
            const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
            defer self.ctx.allocator.free(path);

            self.ctx.printer.append("{s} is outdated, removing.\n", .{entry.name}, .{});
            Fs.deleteFileIfExists(path) catch return Errors.Cache.InvalidFile;
            continue;
        }
        self.ctx.printer.append(" - {s}\n", .{entry.name}, .{});
    }
    if (!is_items_listed) {
        self.ctx.printer.append("No items cached\n", .{}, .{ .color = .red });
    }
    self.ctx.printer.append("\n", .{}, .{});
}

fn cleanOne(self: *Cache, name: []const u8) Errors.Cache!void {
    self.ctx.logger.infof("Cleaing Single {s}", .{name}, @src());

    try self.cleanOneSingle(self.ctx.paths.pkg_cached, name);
}

fn cleanOneSingle(
    self: *Cache,
    cached_path: []const u8,
    id: []const u8,
) Errors.Cache!void {
    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    self.ctx.printer.append("\nCleaning cache with target [{s}]:\n", .{id}, .{});
    var split = std.mem.splitAny(u8, id, "@");

    const name = split.first();
    const version = split.next();

    var data_found: u16 = 0;
    var failed_deletion: u16 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".zep")) {
            const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
            defer self.ctx.allocator.free(path);

            self.ctx.printer.append("{s} is outdated, removing.\n", .{entry.name}, .{});
            continue;
        }

        if (version != null) {
            const entry_name = try std.mem.replaceOwned(
                u8,
                self.ctx.allocator,
                entry.name,
                ".tar.zstd",
                "",
            );
            defer self.ctx.allocator.free(entry_name);
            if (!std.mem.eql(u8, entry_name, id)) continue;
        } else {
            var entry_split = std.mem.splitAny(u8, entry.name, "@");
            const pkg_name = entry_split.first();
            if (!std.mem.startsWith(u8, pkg_name, name)) continue;
        }

        self.ctx.printer.append(" - {s} ", .{entry.name}, .{});

        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);

        Fs.deleteFileIfExists(path) catch {
            failed_deletion += 1;
            self.ctx.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
            continue;
        };
        data_found += 1;
        self.ctx.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
    }
    if (data_found == 0) {
        self.ctx.printer.append("No cached items found.\n", .{}, .{});
        return;
    }
    self.ctx.printer.append("\nRemoved: {d} cached items ({d} failed)\n", .{ data_found, failed_deletion }, .{});
}

fn cleanAllSingle(
    self: *Cache,
    cached_path: []const u8,
) Errors.Cache!void {
    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    var data_found: u16 = 0;
    var failed_deletion: u16 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        self.ctx.printer.append(" - {s} ", .{entry.name}, .{});

        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);

        Fs.deleteFileIfExists(path) catch {
            self.ctx.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
            failed_deletion += 1;
            continue;
        };

        data_found += 1;
        self.ctx.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
    }
    if (data_found == 0) {
        self.ctx.printer.append("No cached items found.\n\n", .{}, .{});
        return;
    }
    self.ctx.printer.append("\nRemoved: {d} cached items ({d} failed)\n\n", .{ data_found, failed_deletion }, .{});
}

pub fn cleanAll(self: *Cache, name: ?[]const u8) Errors.Cache!void {
    self.ctx.logger.info("Cleaning Cache", @src());

    if (name) |n| {
        try self.cleanOne(n);
        return;
    }

    const UNITS = [5][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var unit_depth: u8 = 0;
    var cache_size = try self.getSize();
    while (cache_size > 1024 * 2) {
        unit_depth += 1;
        cache_size = cache_size / 1024;
        if (unit_depth == 4) break;
    }

    if (cache_size == 0) {
        self.ctx.printer.append("Cache is already empty.\n", .{}, .{});
        return;
    }

    const prompt = try std.fmt.allocPrint(self.ctx.allocator, "This will remove all cached items ({d} {s}). Continue? [y/N]", .{ cache_size, UNITS[unit_depth] });
    defer self.ctx.allocator.free(prompt);

    const input = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        prompt,
        .{},
    ) catch return Errors.Cache.OutOfMemory;
    defer self.ctx.allocator.free(input);
    if (input.len == 0) return;
    if (!std.mem.startsWith(u8, input, "y") and !std.mem.startsWith(u8, input, "Y")) return;

    self.ctx.printer.append("Package cleaning:\n", .{}, .{});
    try self.cleanAllSingle(self.ctx.paths.pkg_cached);
    self.ctx.printer.append("Metadata cleaning:\n", .{}, .{});
    try self.cleanAllSingle(self.ctx.paths.meta_cached);
}

fn getSize(self: *Cache) !u64 {
    const b = try self.getSizeSingle(self.ctx.paths.pkg_cached);
    const p = try self.getSizeSingle(self.ctx.paths.pkg_cached);
    const m = try self.getSizeSingle(self.ctx.paths.meta_cached);
    return b + p + m;
}

fn getSizeSingle(
    self: *Cache,
    cached_path: []const u8,
) Errors.Cache!u64 {
    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidFile;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    var cache_size: u64 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);

        var cached_file = Fs.openFile(path) catch return Errors.Cache.InvalidFile;
        defer cached_file.close();

        const stat = cached_file.stat() catch return Errors.Cache.InvalidFile;
        cache_size += stat.size;
    }

    return cache_size;
}

pub fn size(self: *Cache) !void {
    self.ctx.logger.info("Getting Cache Size", @src());

    const UNITS = [5][]const u8{ "B", "KB", "MB", "GB", "TB" };
    blk: {
        var unit_depth: u8 = 0;
        var cache_size = try self.getSizeSingle(self.ctx.paths.pkg_cached);
        while (cache_size > 1024 * 2) {
            unit_depth += 1;
            cache_size = cache_size / 1024;
            if (unit_depth == 4) break;
        }
        self.ctx.printer.append("Package cache size:\n{d} {s}\n\n", .{ cache_size, UNITS[unit_depth] }, .{});
        break :blk;
    }
    blk: {
        var unit_depth: u8 = 0;
        var cache_size = try self.getSizeSingle(self.ctx.paths.meta_cached);
        while (cache_size > 1024 * 2) {
            unit_depth += 1;
            cache_size = cache_size / 1024;
            if (unit_depth == 4) break;
        }
        self.ctx.printer.append("Metadata cache size:\n{d} {s}\n\n", .{ cache_size, UNITS[unit_depth] }, .{});
        break :blk;
    }
}
