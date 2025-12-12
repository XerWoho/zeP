const std = @import("std");
const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

pub fn doctor(
    allocator: std.mem.Allocator,
    printer: *Printer,
    fix_issues: bool,
) !void {
    var is_there_issues = false;

    // First verify that we are in zeP project
    if (!Fs.existsFile(Constants.Extras.package_files.lock)) {
        try printer.append("Lock file schema is missing.\n", .{}, .{ .color = 31 });
    }

    var lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock);
    defer lock.deinit();

    var manifest = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest);
    defer manifest.deinit();

    if (lock.value.schema == Constants.Extras.package_files.lock_schema_version) {
        try printer.append("Lock file schema is fine.\n", .{}, .{ .color = 32 });
    } else if (fix_issues) {
        try printer.append("Lock file schema is NOT matching with zeP version.\n", .{}, .{ .color = 31 });

        lock.value.root = manifest.value;
        lock.value.schema = Constants.Extras.package_files.lock_schema_version;

        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock, lock.value);
        try printer.append("Fixed.\n", .{}, .{ .color = 32 });
    } else {
        is_there_issues = true;
        try printer.append("Lock file schema is NOT matching with zeP version.\n", .{}, .{ .color = 31 });
    }

    const lock_packages = lock.value.packages;
    const manifest_zig_version = manifest.value.zig_version;

    var mismatch_zig_version = false;
    for (lock_packages) |pkg| {
        if (!std.mem.containsAtLeast(u8, pkg.zig_version, 1, manifest_zig_version)) {
            try printer.append(
                "{s} zigs version mismatches\n > Package Zig {s}\n > Project Zig {s}\n",
                .{ pkg.name, pkg.zig_version, manifest_zig_version },
                .{ .color = 31 },
            );
            mismatch_zig_version = true;
        }
    }

    if (!mismatch_zig_version) {
        try printer.append("No issues with zig versions mismatch [packages]!\n", .{}, .{ .color = 32 });
    }

    const lock_root_json = try std.json.stringifyAlloc(allocator, lock.value.root, .{});
    const manifest_root_json = try std.json.stringifyAlloc(allocator, manifest.value, .{});

    const manifest_from_lock = std.hash.Wyhash.hash(0, lock_root_json);
    const manifest_main = std.hash.Wyhash.hash(0, manifest_root_json);
    if (manifest_from_lock == manifest_main) {
        try printer.append("Lock root matches zep.json.\n", .{}, .{ .color = 32 });
    } else if (fix_issues) {
        try printer.append("Lock file schema root is not matching with zep.json.\n", .{}, .{ .color = 31 });
        lock.value.root = manifest.value;
        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock, lock.value);
        try printer.append("Fixed.\n\n", .{}, .{ .color = 32 });
    } else {
        is_there_issues = true;
        try printer.append("Lock file schema root is not matching with zep.json.\n", .{}, .{ .color = 31 });
    }

    var missing_packages = false;
    const manifest_packages = manifest.value.packages;
    for (manifest_packages) |m_package_id| {
        var is_package_in_lock = false;
        for (lock.value.packages) |l_package| {
            const l_package_id = l_package.name;
            if (std.mem.eql(u8, l_package_id, m_package_id)) {
                is_package_in_lock = true;
                break;
            }
        }

        if (!is_package_in_lock) {
            missing_packages = true;
            break;
        }
    }

    if (!missing_packages and lock.value.packages.len == manifest.value.packages.len) {
        try printer.append("Lock file packages match exactly with zep.json!\n\n", .{}, .{ .color = 32 });
    } else if (fix_issues) {
        try printer.append("Lock file packages mismatch with zep.json.\nzep.lock has priority!\n", .{}, .{ .color = 31 });

        var pkg = std.ArrayList([]const u8).init(allocator);
        defer pkg.deinit();

        for (lock.value.packages) |lock_package| {
            try pkg.append(lock_package.name);
        }
        manifest.value.packages = pkg.items;
        try Manifest.writeManifest(Structs.ZepFiles.PackageJsonStruct, allocator, Constants.Extras.package_files.manifest, manifest.value);
        try printer.append("Fixed.\n\n", .{}, .{ .color = 32 });
    } else {
        is_there_issues = true;
        try printer.append("Lock file packages mismatch with zep.json.\n", .{}, .{ .color = 31 });
    }

    if (is_there_issues and !fix_issues) {
        try printer.append("\nRun\n $ zep doctor --fix\n\nTo fix the mentioned issues automatically.\n\n", .{}, .{});
    }
}
