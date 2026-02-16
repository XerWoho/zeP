const std = @import("std");
const builtin = @import("builtin");

pub const ArtifactCache = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Manifest = @import("core").Manifest;

const Context = @import("context");

/// Lists installed Artifact versions
ctx: *Context,
artifact_type: Structs.Extras.ArtifactType,

pub fn init(
    ctx: *Context,
    artifact_type: Structs.Extras.ArtifactType,
) ArtifactCache {
    return ArtifactCache{
        .ctx = ctx,
        .artifact_type = artifact_type,
    };
}

pub fn deinit(_: *ArtifactCache) void {
    // currently no deinit required
}

pub fn list(self: *ArtifactCache) Errors.Cache!void {
    self.ctx.logger.info("Listing ArtifactCache", @src());

    const cached_path = try std.fs.path.join(self.ctx.allocator, &.{
        if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "z",
    });
    defer self.ctx.allocator.free(cached_path);

    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    self.ctx.printer.append("Listing cached artifacts:\n", .{}, .{});
    var is_artifacts_listed = false;
    while (opened_cached_iter.next() catch return Errors.Cache.InvalidDir) |entry| {
        if (entry.kind != .directory) continue;
        is_artifacts_listed = true;

        const single_cache_path = try std.fs.path.join(self.ctx.allocator, &.{
            cached_path,
            entry.name,
        });
        defer {
            self.ctx.allocator.free(single_cache_path);
        }

        var version_directory = Fs.openDir(single_cache_path) catch return Errors.Cache.InvalidDir;
        defer version_directory.close();

        var version_iterator = version_directory.iterate();
        var found_targets: bool = false;

        while (version_iterator.next() catch return Errors.Cache.InvalidDir) |version_entry| {
            found_targets = true;
            const target_name = try self.ctx.allocator.dupe(u8, version_entry.name);
            self.ctx.printer.append(" > {s}\n", .{target_name}, .{});
        }

        if (!found_targets) {
            self.ctx.printer.append(" NOTHING CACHED\n", .{}, .{ .color = .red });
        }
    }
    if (!is_artifacts_listed) {
        self.ctx.printer.append("No artifacts cached.\n", .{}, .{ .color = .red });
    }
    self.ctx.printer.append("\n", .{}, .{});
}

pub fn cleanOne(self: *ArtifactCache, version: []const u8) Errors.Cache!void {
    self.ctx.logger.infof("Cleaing Single Artifact {s}", .{version}, @src());
    const cached_path = try std.fs.path.join(self.ctx.allocator, &.{
        if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "z",
    });
    defer self.ctx.allocator.free(cached_path);

    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    self.ctx.printer.append("Cleaning cache with target [{s}]:\n", .{version}, .{});
    var data_found: u16 = 0;
    var failed_deletion: u16 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.InvalidDir) |entry| {
        if (std.mem.eql(u8, entry.name, version)) continue;

        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);

        Fs.deleteTreeIfExists(path) catch {
            failed_deletion += 1;
            self.ctx.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
            continue;
        };
        data_found += 1;
        self.ctx.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
    }
    if (data_found == 0) {
        self.ctx.printer.append("No cached artifacts found.\n", .{}, .{});
        return;
    }
    self.ctx.printer.append("Removed: {d} cached artifacts ({d} failed)\n", .{ data_found, failed_deletion }, .{});
}

pub fn cleanAll(self: *ArtifactCache) Errors.Cache!void {
    self.ctx.logger.info("Cleaning ArtifactCache", @src());

    const cached_path = try std.fs.path.join(self.ctx.allocator, &.{
        if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "z",
    });
    defer self.ctx.allocator.free(cached_path);

    var opened_cached = Fs.openOrCreateDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    self.ctx.printer.append("Cleaning cache:\n", .{}, .{});

    const UNITS = [5][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var unit_depth: u8 = 0;
    var cache_size = try self.getSize();
    while (cache_size > 1024 * 2) {
        unit_depth += 1;
        cache_size = cache_size / 1024;
        if (unit_depth == 4) break;
    }

    if (cache_size == 0) {
        self.ctx.printer.append("ArtifactCache is already empty.\n", .{}, .{});
        return;
    }

    const prompt = try std.fmt.allocPrint(self.ctx.allocator, "This will remove all cached {s} artifacts ({d} {s}). Continue? [y/N]", .{
        if (self.artifact_type == .zig) "Zig" else "Zep",
        cache_size,
        UNITS[unit_depth],
    });
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

    var data_found: u16 = 0;
    var failed_deletion: u16 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);
        self.ctx.printer.append(" - {s} [{s}]", .{ entry.name, path }, .{});

        Fs.deleteTreeIfExists(path) catch {
            self.ctx.printer.append(" <FAILED>\n", .{}, .{ .color = .red });
            failed_deletion += 1;
            continue;
        };

        data_found += 1;
        self.ctx.printer.append(" <REMOVED>\n", .{}, .{ .color = .green });
    }
    if (data_found == 0) {
        self.ctx.printer.append("No cached artifacts found.\n", .{}, .{});
        return;
    }
    self.ctx.printer.append("\nRemoved: {d} cached artifacts ({d} failed)\n", .{ data_found, failed_deletion }, .{});
}

fn getFsSize(self: *ArtifactCache, cached_path: []const u8) Errors.Cache!u64 {
    if (!Fs.existsDir(cached_path)) return 0;

    var opened_cached = Fs.openDir(cached_path) catch return Errors.Cache.InvalidDir;
    defer opened_cached.close();

    var opened_cached_iter = opened_cached.iterate();

    var cache_size: u64 = 0;
    while (opened_cached_iter.next() catch return Errors.Cache.DirFailed) |entry| {
        const path = try std.fs.path.join(self.ctx.allocator, &.{ cached_path, entry.name });
        defer self.ctx.allocator.free(path);

        if (entry.kind == .directory) {
            const u = try self.getFsSize(path);
            cache_size += u;
            continue;
        }

        var cached_file = Fs.openFile(path) catch return Errors.Cache.InvalidFile;
        defer cached_file.close();

        const stat = cached_file.stat() catch return Errors.Cache.InvalidFile;
        cache_size += stat.size;
    }

    return cache_size;
}

fn getSize(self: *ArtifactCache) Errors.Cache!u64 {
    const cached_path = try std.fs.path.join(self.ctx.allocator, &.{
        if (self.artifact_type == .zig) self.ctx.paths.zig_root else self.ctx.paths.zep_root,
        "z",
    });
    defer self.ctx.allocator.free(cached_path);

    const cache_size: u64 = try self.getFsSize(cached_path);
    return cache_size;
}

pub fn size(self: *ArtifactCache) Errors.Cache!void {
    self.ctx.logger.info("Getting ArtifactCache Size", @src());

    self.ctx.printer.append("Getting cache size...\n", .{}, .{});
    const cache_size = try self.getSize();
    self.ctx.printer.append("Size:\n{d} Bytes\n{d} KB\n{d} MB\n\n", .{
        cache_size,
        cache_size / 1024,
        cache_size / 1024 / 1024,
    }, .{});
}
