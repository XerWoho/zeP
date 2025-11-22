const std = @import("std");

const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const UtilsFs =
    @import("fs.zig");
const UtilsHash =
    @import("hash.zig");
const UtilsJson =
    @import("json.zig");
const UtilsPrinter =
    @import("printer.zig");
const UtilsManifest =
    @import("manifest.zig");

pub const Package = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,

    packageHash: []u8,
    packageName: []const u8,
    packageVersion: []const u8,
    package: Structs.PackageVersions,

    id: []u8, // <-- packageName@packageVersion

    printer: *UtilsPrinter.Printer,

    pub fn init(
        allocator: std.mem.Allocator,
        packageName: []const u8,
        packageVersion: ?[]const u8,
        printer: *UtilsPrinter.Printer,
    ) !?Package {
        try printer.append("\nFinding the package...\n", .{}, .{});

        // JSON context
        var json = try UtilsJson.Json.init(allocator);

        // Load package manifest
        const parsedPkg = try json.parsePackage(packageName);
        if (parsedPkg == null) {
            try printer.append("Package not found...\n\n", .{}, .{ .color = 31 });
            return null;
        }
        defer parsedPkg.?.deinit();

        try printer.append("Package Found! - {s}.json\n\n", .{packageName}, .{ .color = 32 });

        const versions = parsedPkg.?.value.versions;
        if (versions.len == 0) {
            @panic("Package has no versions!");
        }

        // Pick target version
        const targetVersion = packageVersion orelse versions[0].version;

        try printer.append("Getting the package version...\n", .{}, .{});
        try printer.append("Target Version: ", .{}, .{});

        if (packageVersion) |v| {
            try printer.append("{s}", .{v}, .{});
        } else {
            try printer.append("/ (no version specified, using latest)", .{}, .{});
        }
        try printer.append("\n\n", .{}, .{});

        // Find version struct
        var selected: ?Structs.PackageVersions = null;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, targetVersion)) {
                selected = v;
                break;
            }
        }

        if (selected == null) {
            try printer.append("Package version was not found...\n\n", .{}, .{ .color = 31 });
            std.process.exit(0);
        }

        try printer.append("Package version found!\n\n", .{}, .{ .color = 32 });

        // Create hash
        const hash = try UtilsHash.hashData(allocator, selected.?.url);

        // Compute id
        const id = try std.fmt.allocPrint(allocator, "{s}@{s}", .{
            packageName,
            targetVersion,
        });

        return Package{
            .allocator = allocator,
            .json = json,
            .packageName = packageName,
            .packageVersion = targetVersion,
            .packageHash = hash,
            .package = selected.?,
            .printer = printer,
            .id = id,
        };
    }

    pub fn deinit(_: *Package) void {}

    fn getPackageNames(self: *Package) !std.ArrayList([]const u8) {
        if (!UtilsFs.checkFileExists(Constants.ROOT_ZEP_ZEP_MANIFEST)) {
            var tmp = try std.fs.cwd().createFile(Constants.ROOT_ZEP_ZEP_MANIFEST, .{});
            defer tmp.close();
            try self.json.writePretty(Constants.ROOT_ZEP_ZEP_MANIFEST, Structs.ZepManifest{
                .path = "",
                .version = "",
            });
        }

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

        try self.printer.append(try customPackageNames.toOwnedSlice(), .{}, .{});
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

        if (localSuggestions.items.len == 0 and customSuggestions.items.len == 0) {
            const noPkg = try std.fmt.allocPrint(self.printer.allocator, "(404) No package named '{s}' found.\nCheck for typos!\n", .{self.packageName});
            try self.printer.append(noPkg, .{}, .{});
            return null;
        }
        const noPkg = try std.fmt.allocPrint(self.printer.allocator, "(404) No package named '{s}' found.\nDid you mean:\n", .{self.packageName});
        try self.printer.append(noPkg, .{}, .{});
        for (localSuggestions.items) |s| {
            const pkg = try std.fmt.allocPrint(self.printer.allocator, "- {s} (local)\n", .{s});
            try self.printer.append(pkg, .{}, .{});
        }
        try self.printer.append("\n", .{}, .{});
        for (customSuggestions.items) |s| {
            const pkg = try std.fmt.allocPrint(self.printer.allocator, "- {s} (custom)\n", .{s});
            try self.printer.append(pkg, .{}, .{});
        }
        try self.printer.append("\n", .{}, .{});

        return null;
    }

    // --- PACKAGE-FILES ---

    pub fn manifestAdd(self: *Package, pkg: *Structs.PackageJsonStruct) !void {
        pkg.packages = try filterOut(
            self.allocator,
            pkg.packages,
            self.packageName,
            []const u8,
            struct {
                fn match(a: []const u8, b: []const u8) bool {
                    return std.mem.startsWith(u8, a, b); // first remove the previous package Name
                }
            }.match,
        );

        pkg.packages = try appendUnique(
            []const u8,
            pkg.packages,
            self.id,
            self.allocator,
            struct {
                fn match(a: []const u8, b: []const u8) bool {
                    return std.mem.startsWith(u8, a, b);
                }
            }.match,
        );

        try self.json.writePretty(Constants.ZEP_PACKAGE_FILE, pkg);
    }

    pub fn manifestRemove(self: *Package, pkg: *Structs.PackageJsonStruct) !void {
        pkg.packages = try filterOut(
            self.allocator,
            pkg.packages,
            self.id,
            []const u8,
            struct {
                fn match(item: []const u8, ctx: []const u8) bool {
                    return std.mem.startsWith(u8, item, ctx);
                }
            }.match,
        );

        try self.json.writePretty(Constants.ZEP_PACKAGE_FILE, pkg);
    }

    pub fn lockAdd(self: *Package, lock: *Structs.PackageLockStruct) !void {
        const new_entry = Structs.LockPackageStruct{
            .name = self.id,
            .hash = self.packageHash,
            .source = self.package.url,
            .zigVersion = self.package.zigVersion,
            .rootFile = self.package.rootFile,
        };

        lock.packages = try filterOut(
            self.allocator,
            lock.packages,
            self.packageName,
            Structs.LockPackageStruct,
            struct {
                fn match(item: Structs.LockPackageStruct, ctx: []const u8) bool {
                    return std.mem.startsWith(u8, item.name, ctx);
                }
            }.match,
        );

        lock.packages = try appendUnique(
            Structs.LockPackageStruct,
            lock.packages,
            new_entry,
            self.allocator,
            struct {
                fn match(item: Structs.LockPackageStruct, ctx: Structs.LockPackageStruct) bool {
                    return std.mem.startsWith(u8, item.name, ctx.name);
                }
            }.match,
        );

        var packageJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);
        defer packageJson.deinit();
        lock.root = packageJson.value;

        try self.json.writePretty(Constants.ZEP_LOCK_PACKAGE_FILE, lock);
    }

    pub fn lockRemove(self: *Package, lock: *Structs.PackageLockStruct) !void {
        lock.packages = try filterOut(
            self.allocator,
            lock.packages,
            self.packageName,
            Structs.LockPackageStruct,
            struct {
                fn match(item: Structs.LockPackageStruct, ctx: []const u8) bool {
                    return std.mem.startsWith(u8, item.name, ctx);
                }
            }.match,
        );

        var packageJson = try UtilsManifest.readManifest(Structs.PackageJsonStruct, self.allocator, Constants.ZEP_PACKAGE_FILE);
        defer packageJson.deinit();
        lock.root = packageJson.value;

        try self.json.writePretty(Constants.ZEP_LOCK_PACKAGE_FILE, lock);
    }
};

fn filterOut(
    allocator: std.mem.Allocator,
    list: anytype,
    filter: []const u8,
    comptime T: type,
    matchFn: fn (a: T, b: []const u8) bool,
) ![]T {
    var out = std.ArrayList(T).init(allocator);
    defer out.deinit();

    for (list) |item| {
        if (!matchFn(item, filter))
            try out.append(item);
    }

    return out.toOwnedSlice();
}

fn appendUnique(
    comptime T: type,
    list: []const T,
    new_item: T,
    allocator: std.mem.Allocator,
    matchFn: fn (a: T, b: T) bool,
) ![]T {
    var arr = std.ArrayList(T).init(allocator);
    defer arr.deinit();

    for (list) |item| {
        try arr.append(item);
        if (matchFn(item, new_item))
            return arr.toOwnedSlice();
    }

    try arr.append(new_item);
    return arr.toOwnedSlice();
}

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
