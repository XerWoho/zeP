const std = @import("std");
const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest.Manifest;

pub fn doctor(
    allocator: std.mem.Allocator,
    printer: *Printer,
    manifest: *Manifest,
    fix_issues: bool,
) !void {
    var is_there_issues = false;

    // First verify that we are in zep project
    if (!Fs.existsFile(Constants.Extras.package_files.lock)) {
        try printer.append("Lock file schema is missing.\n", .{}, .{ .color = .red });
    }

    var lock = try manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );
    defer lock.deinit();

    var read_manifest = try manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer read_manifest.deinit();

    if (lock.value.schema == Constants.Extras.package_files.lock_schema_version) {
        try printer.append("Lock file schema is fine.\n", .{}, .{ .color = .green });
    } else if (fix_issues) {
        try printer.append("Lock file schema is NOT matching with zep version.\n", .{}, .{ .color = .red });

        lock.value.root = read_manifest.value;
        lock.value.schema = Constants.Extras.package_files.lock_schema_version;

        try manifest.writeManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
            lock.value,
        );
        try printer.append("Fixed.\n", .{}, .{ .color = .green });
    } else {
        is_there_issues = true;
        try printer.append("Lock file schema is NOT matching with zep version.\n", .{}, .{ .color = .red });
    }

    const lock_packages = lock.value.packages;
    const manifest_zig_version = read_manifest.value.zig_version;

    var mismatch_zig_version = false;
    for (lock_packages) |pkg| {
        if (!std.mem.containsAtLeast(u8, pkg.zig_version, 1, manifest_zig_version)) {
            try printer.append(
                "{s} zigs version mismatches\n > Package Zig {s}\n > Project Zig {s}\n",
                .{ pkg.name, pkg.zig_version, manifest_zig_version },
                .{ .color = .red },
            );
            mismatch_zig_version = true;
        }
    }

    if (!mismatch_zig_version) {
        try printer.append("No issues with zig versions mismatch [packages]!\n", .{}, .{ .color = .green });
    }

    const lock_root_json = try std.json.Stringify.valueAlloc(allocator, lock.value.root, .{});
    const manifest_root_json = try std.json.Stringify.valueAlloc(allocator, read_manifest.value, .{});

    const manifest_from_lock = std.hash.Wyhash.hash(0, lock_root_json);
    const manifest_main = std.hash.Wyhash.hash(0, manifest_root_json);
    if (manifest_from_lock == manifest_main) {
        try printer.append("Lock root matches zep.json.\n", .{}, .{ .color = .green });
    } else if (fix_issues) {
        try printer.append("Lock file schema root is not matching with zep.json.\n", .{}, .{ .color = .red });
        lock.value.root = read_manifest.value;
        try manifest.writeManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
            lock.value,
        );
        try printer.append("Fixed.\n\n", .{}, .{ .color = .green });
    } else {
        is_there_issues = true;
        try printer.append("Lock file schema root is not matching with zep.json.\n", .{}, .{ .color = .red });
    }

    var missing_packages = false;
    const manifest_packages = read_manifest.value.packages;
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

    if (!missing_packages and lock.value.packages.len == read_manifest.value.packages.len) {
        try printer.append("Lock file packages match exactly with zep.json!\n\n", .{}, .{ .color = .green });
    } else if (fix_issues) {
        try printer.append("Lock file packages mismatch with zep.json.\nzep.lock has priority!\n", .{}, .{ .color = .red });

        var pkg = try std.ArrayList([]const u8).initCapacity(allocator, 20);
        defer pkg.deinit(allocator);

        for (lock.value.packages) |lock_package| {
            try pkg.append(allocator, lock_package.name);
        }
        read_manifest.value.packages = pkg.items;
        try manifest.writeManifest(
            Structs.ZepFiles.PackageJsonStruct,
            Constants.Extras.package_files.manifest,
            read_manifest.value,
        );
        try printer.append("Fixed.\n\n", .{}, .{ .color = .green });
    } else {
        is_there_issues = true;
        try printer.append("Lock file packages mismatch with zep.json.\n", .{}, .{ .color = .red });
    }

    if (is_there_issues and !fix_issues) {
        try printer.append("\nRun\n $ zep doctor --fix\n\nTo fix the mentioned issues automatically.\n\n", .{}, .{});
    }
}
