const std = @import("std");

const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const UtilsFs =
    @import("fs.zig");
const UtilsJson =
    @import("json.zig");
const UtilsPrinter =
    @import("printer.zig");

pub const Package = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,

    packageFingerprint: []u8,
    packageName: []const u8,
    packageParsed: std.json.Parsed(Structs.PackageStruct),
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, packageName: []const u8, printer: *UtilsPrinter.Printer) !?Package {
        var json = try UtilsJson.Json.init(allocator);
        if (Locales.VERBOSITY_MODE >= 1) {
            try printer.append("\nFinding the package...\n\n");
        }
        const parsePackage = try json.parsePackage(packageName);
        if (parsePackage == null) {
            if (Locales.VERBOSITY_MODE >= 1) {
                try printer.append("\nPackage not found...\n\n");
            }
            return null;
        } else {
            if (Locales.VERBOSITY_MODE >= 1) {
                const find = try std.fmt.allocPrint(allocator, "Package Found! - {s}.json\n\n", .{packageName});
                try printer.append(find);
            }
        }

        const fingerprint = try hashData(parsePackage.?.value);

        return Package{ .allocator = allocator, .json = json, .packageFingerprint = fingerprint, .packageName = packageName, .packageParsed = parsePackage.?, .printer = printer };
    }

    pub fn deinit(self: *Package) void {
        self.packageParsed.deinit();
    }

    fn getPackageNames(self: *Package) !std.ArrayList([]const u8) {
        const manifestTarget = Constants.ROOT_ZEP_ZEP_MANIFEST;
        const openManifest = try UtilsFs.openFile(manifestTarget);
        defer openManifest.close();

        const readOpenManifest = try openManifest.readToEndAlloc(self.allocator, 1024 * 1024);
        const parsedManifest = try std.json.parseFromSlice(Structs.ZepManifest, self.allocator, readOpenManifest, .{});
        defer parsedManifest.deinit();
        const localPath = try std.fmt.allocPrint(self.allocator, "{s}/packages/", .{parsedManifest.value.path});
        defer self.allocator.free(localPath);

        const dir = try UtilsFs.openDir(localPath);
        defer dir.close();

        var names = std.ArrayList([]const u8).init(self.allocator);
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            const name = entry.name[0 .. entry.name.len - 5];
            try names.append(try self.allocator.dupe(u8, name));
        }

        return names;
    }

    fn getCustomPackageNames(self: *Package) !std.ArrayList([]const u8) {
        const dir = try UtilsFs.openDir(Constants.ROOT_ZEP_CUSTOM_PACKAGES);
        defer dir.close();

        var names = std.ArrayList([]const u8).init(self.allocator);
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            const name = entry.name[0 .. entry.name.len - 5];
            try names.append(try self.allocator.dupe(u8, name));
        }

        return names;
    }

    pub fn findPackage(self: *Package) !?[]const u8 {
        const localPackageNames = try self.getPackageNames();
        defer {
            for (localPackageNames.items) |n| self.allocator.free(n);
            localPackageNames.deinit();
        }
        var localSuggestions = std.ArrayList([]const u8).init(self.allocator);
        defer localSuggestions.deinit();
        for (localPackageNames.items) |pn| {
            const dist = hammingDistance(pn, self.packageName);
            if (dist == 0) {
                const found = try self.allocator.dupe(u8, pn);
                return found;
            } else if (dist < 3) {
                try localSuggestions.append(pn);
            }
        }

        const customPackageNames = try self.getCustomPackageNames();
        defer {
            for (customPackageNames.items) |n| self.allocator.free(n);
            customPackageNames.deinit();
        }

        try self.printer.append(try customPackageNames.toOwnedSlice());
        var customSuggestions = std.ArrayList([]const u8).init(self.allocator);
        defer customSuggestions.deinit();
        for (customPackageNames.items) |pn| {
            const dist = hammingDistance(pn, self.packageName);
            if (dist == 0) {
                const found = try self.allocator.dupe(u8, pn);
                return found;
            } else if (dist < 3) {
                try customSuggestions.append(pn);
            }
        }

        if (Locales.VERBOSITY_MODE >= 1) {
            if (localSuggestions.items.len == 0 and customSuggestions.items.len == 0) {
                const noPkg = try std.fmt.allocPrint(self.printer.allocator, "(404) No package named '{s}' found.\nCheck for typos!\n", .{self.packageName});
                try self.printer.append(noPkg);
                return null;
            }
            const noPkg = try std.fmt.allocPrint(self.printer.allocator, "(404) No package named '{s}' found.\nDid you mean:\n", .{self.packageName});
            try self.printer.append(noPkg);
            for (localSuggestions.items) |s| {
                const pkg = try std.fmt.allocPrint(self.printer.allocator, "- {s} (local)\n", .{s});
                try self.printer.append(pkg);
            }
            try self.printer.append("\n");
            for (customSuggestions.items) |s| {
                const pkg = try std.fmt.allocPrint(self.printer.allocator, "- {s} (custom)\n", .{s});
                try self.printer.append(pkg);
            }
            try self.printer.append("\n");
        }

        return null;
    }

    fn setFingerprint(self: *Package) !void {
        if (!try UtilsFs.checkFileExists(Constants.ROOT_ZEP_FINGERPRINTS_FILE)) {
            _ = try std.fs.cwd().createFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE, .{});
        }

        var file = try std.fs.cwd().openFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE, .{ .mode = .read_write });
        defer file.close();

        const entry = try std.fmt.allocPrint(self.allocator, "{s}:{s}\n", .{ self.packageName, self.packageFingerprint });
        defer self.allocator.free(entry);

        _ = try file.seekTo(try file.getEndPos());
        _ = try file.write(entry);
    }

    pub fn getFingerprint(self: *Package) !?[]u8 {
        var file = try UtilsFs.openCFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE);
        defer file.close();

        const reader = file.reader();
        while (try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1028 * 1028)) |line| {
            defer self.allocator.free(line);
            var it = std.mem.splitScalar(u8, line, ':');
            if (std.mem.eql(u8, it.first(), self.packageName)) {
                const cHash = it.next() orelse return "";
                return try self.allocator.dupe(u8, cHash);
            }
        }
        return null;
    }

    pub fn delFingerprint(self: *Package) !void {
        var file = try std.fs.cwd().openFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE, .{ .mode = .read_write });
        defer file.close();

        const reader = file.reader();
        var remaining = std.ArrayList([]u8).init(self.allocator);
        defer remaining.deinit();

        while (try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1028 * 1028)) |line| {
            var it = std.mem.splitScalar(u8, line, ':');
            if (!std.mem.eql(u8, it.first(), self.packageName)) {
                try remaining.append(line);
            } else {
                self.allocator.free(line);
            }
        }

        const tmpPath = "fingerprint.tmp";
        var tmpFile = try std.fs.cwd().createFile(tmpPath, .{ .truncate = true });
        defer tmpFile.close();

        for (remaining.items) |line| {
            _ = try tmpFile.write(line);
            _ = try tmpFile.write("\n");
            self.allocator.free(line);
        }

        try std.fs.cwd().deleteFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE);
        try std.fs.cwd().rename(tmpPath, Constants.ROOT_ZEP_FINGERPRINTS_FILE);
    }

    fn compareFingerprint(self: *Package) !bool {
        if (try self.getFingerprint()) |existing| {
            defer self.allocator.free(existing);
            if (std.mem.eql(u8, existing, self.packageFingerprint)) {
                if (Locales.VERBOSITY_MODE >= 1)
                    try self.printer.append(" > FINGERPRINT ALREADY EXISTS!\n");
                return true;
            }
            try self.delFingerprint();
            if (Locales.VERBOSITY_MODE >= 1)
                try self.printer.append(" > DELETED PREVIOUS FINGERPRINT\n");
        }
        return false;
    }

    pub fn checkFingerprint(self: *Package) !bool {
        if (try self.compareFingerprint()) return true;
        try self.setFingerprint();
        if (Locales.VERBOSITY_MODE >= 1)
            try self.printer.append(" > FINGERPRINT SET\n\n");

        return false;
    }

    // ----

    fn updatePkgFile(self: *Package, pkg: *Structs.PackageJsonStruct) !void {
        const str = try std.json.stringifyAlloc(self.allocator, pkg, .{ .whitespace = .indent_2 });
        try self.writePkg(str);
    }

    fn updateLockFile(self: *Package, lock: *Structs.PackageLockStruct) !void {
        const str = try std.json.stringifyAlloc(self.allocator, lock, .{ .whitespace = .indent_2 });
        try self.writeLock(str);
    }

    fn writePkg(_: *Package, pkgString: []const u8) !void {
        _ = std.fs.cwd().createFile(Constants.ZEP_PACKAGE_FILE, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const pFile = try std.fs.cwd().openFile(Constants.ZEP_PACKAGE_FILE, std.fs.File.OpenFlags{ .mode = .read_write });
        _ = try pFile.write(pkgString);
    }

    fn writeLock(_: *Package, lockString: []const u8) !void {
        _ = std.fs.cwd().createFile(Constants.ZEP_LOCK_PACKAGE_FILE, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const lFile = try std.fs.cwd().openFile(Constants.ZEP_LOCK_PACKAGE_FILE, std.fs.File.OpenFlags{ .mode = .read_write });
        _ = try lFile.write(lockString);
    }

    pub fn pkgAppendPackage(self: *Package, pkg: *Structs.PackageJsonStruct) !void {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        for (pkg.packages) |p| {
            try list.append(p);
            if (std.mem.eql(u8, p, self.packageName))
                return;
        }

        try list.append(self.packageName);
        pkg.packages = list.items;
        try self.updatePkgFile(pkg);
    }

    pub fn pkgRemovePackage(self: *Package, pkg: *Structs.PackageJsonStruct) !void {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        for (pkg.packages) |p| {
            if (!std.mem.eql(u8, p, self.packageName))
                try list.append(p);
        }

        pkg.packages = list.items;
        try self.updatePkgFile(pkg);
    }

    pub fn lockAppendPackage(self: *Package, lock: *Structs.PackageLockStruct) !void {
        var list = std.ArrayList(Structs.LockPackageStruct).init(self.allocator);
        defer list.deinit();

        for (lock.packages) |p| {
            try list.append(p);
            if (std.mem.eql(u8, p.name, self.packageName))
                return;
        }

        try list.append(.{
            .name = self.packageName,
            .fingerprint = self.packageFingerprint,
            .author = self.packageParsed.value.author,
            .source = self.packageParsed.value.git,
        });

        const pkg = try self.json.parsePkgJson();
        defer {
            if (pkg) |p| {
                p.deinit();
            }
        }
        if (pkg) |p| {
            lock.root = p.value;
        }

        lock.packages = list.items;
        try self.updateLockFile(lock);
    }

    pub fn lockRemovePackage(self: *Package, lock: *Structs.PackageLockStruct) !void {
        var list = std.ArrayList(Structs.LockPackageStruct).init(self.allocator);
        defer list.deinit();

        for (lock.packages) |p| {
            if (!std.mem.eql(u8, p.name, self.packageName))
                try list.append(p);
        }

        const pkg = try self.json.parsePkgJson();
        defer {
            if (pkg) |p| {
                p.deinit();
            }
        }
        if (pkg) |p| {
            lock.root = p.value;
        }

        lock.packages = list.items;
        try self.updateLockFile(lock);
    }
};

fn absDiff(x: usize, y: usize) usize {
    return @as(usize, @abs(@as(i64, @intCast(x)) - @as(i64, @intCast(y))));
}

fn hammingDistance(s1: []const u8, s2: []const u8) usize {
    const minLen = if (s1.len < s2.len) s1.len else s2.len;
    var dist = absDiff(s1.len, s2.len);
    var i: usize = 0;
    while (i < minLen) : (i += 1) {
        if (s1[i] != s2[i]) dist += 1;
    }
    return dist;
}

fn hashData(data: Structs.PackageStruct) ![]u8 {
    const allocator = std.heap.page_allocator;
    const jsonData = try std.json.stringifyAlloc(allocator, data, .{});
    defer allocator.free(jsonData);
    const hash = std.hash.murmur.Murmur2_64.hash(jsonData);
    return try std.fmt.allocPrint(allocator, "{d}", .{hash});
}
