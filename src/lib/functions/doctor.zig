const std = @import("std");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Context = @import("context");

pub fn doctor(
    ctx: *Context,
    fix_issues: bool,
) !void {
    ctx.logger.info("Running Doctor", @src());

    var is_there_issues = false;

    // First verify that we are in zep project
    if (!Fs.existsFile(Constants.Default.package_files.lock)) {
        ctx.printer.append("Lock file schema is missing.\n", .{}, .{ .color = .red });
    }

    var lock = try ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();

    if (lock.value.schema == Constants.Default.package_files.lock_schema_version) {
        ctx.printer.append("Lock file schema is fine.\n", .{}, .{ .color = .green });
    } else if (fix_issues) {
        ctx.printer.append("Lock file schema is NOT matching with zep version.\n", .{}, .{ .color = .red });
        lock.value.schema = Constants.Default.package_files.lock_schema_version;

        try ctx.manifest.writeManifest(
            Structs.ZepFiles.Lock,
            Constants.Default.package_files.lock,
            lock.value,
        );
        ctx.printer.append("Fixed.\n", .{}, .{ .color = .green });
    } else {
        is_there_issues = true;
        ctx.printer.append("Lock file schema is NOT matching with zep version.\n", .{}, .{ .color = .red });
    }

    const lock_packages = lock.value.packages;
    const lock_zig_version = lock.value.root.zig_version;

    var mismatch_zig_version = false;
    for (lock_packages) |pkg| {
        if (!std.mem.containsAtLeast(u8, pkg.zig_version, 1, lock_zig_version)) {
            ctx.printer.append(
                "{s} zig versions mismatch\n > Package Zig {s}\n > Project Zig {s}\n",
                .{ pkg.name, pkg.zig_version, lock_zig_version },
                .{ .color = .red },
            );
            mismatch_zig_version = true;
        }
    }

    if (!mismatch_zig_version) {
        ctx.printer.append("No issues with zig versions [packages]!\n", .{}, .{ .color = .green });
    }

    var missing_packages = false;
    const manifest_packages = lock.value.root.packages;
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

    if (is_there_issues and !fix_issues) {
        ctx.printer.append("Run\n $ zep doctor --fix\n\nTo fix the mentioned issues automatically.\n\n", .{}, .{});
    }
}
