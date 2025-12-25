const std = @import("std");
const clap = @import("clap");

const DoctorArgs = struct {
    fix: bool,
};
pub fn parseDoctor() !DoctorArgs {
    const params = comptime clap.parseParamsComptime(
        \\-f, --fix             Display this help and exit.
        \\<str>...
        \\
    );

    const allocator = std.heap.page_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    return DoctorArgs{
        .fix = res.args.fix != 0,
    };
}

const UninstallArgs = struct {
    global: bool,
    force: bool,
};
pub fn parseUninstall() !UninstallArgs {
    const params = comptime clap.parseParamsComptime(
        \\-g, --global             Display this help and exit.
        \\-f, --force             Display this help and exit.
        \\<str>...
        \\
    );

    const allocator = std.heap.page_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    return UninstallArgs{
        .global = res.args.global != 0,
        .force = res.args.force != 0,
    };
}

const InstallArgs = struct {
    inject: bool,
    unverified: bool,
};
pub fn parseInstall() !InstallArgs {
    const params = comptime clap.parseParamsComptime(
        \\-i, --inject             Display this help and exit.
        \\-u, --unverified             Display this help and exit.
        \\<str>...
        \\
    );

    const allocator = std.heap.page_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    return InstallArgs{
        .inject = res.args.inject != 0,
        .unverified = res.args.unverified != 0,
    };
}

const BootstrapArgs = struct {
    zig: []const u8,
    deps: [][]const u8,
};
pub fn parseBootstrap() !BootstrapArgs {
    const params = comptime clap.parseParamsComptime(
        \\-z, --zig <str>  An option parameter which can be specified multiple times.
        \\-d, --deps <str>  An option parameter which can be specified multiple times.
        \\<str>...
        \\
    );

    const allocator = std.heap.page_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const zig: []const u8 = res.args.zig orelse "0.14.0";
    const raw_deps: []const u8 = res.args.deps orelse "";

    var deps = try std.ArrayList([]const u8).initCapacity(allocator, 20);
    var deps_split = std.mem.splitScalar(u8, raw_deps, ',');
    while (deps_split.next()) |d| {
        const dep = std.mem.trim(u8, d, " ");
        if (dep.len == 0) continue;
        try deps.append(allocator, try allocator.dupe(u8, dep));
    }

    return BootstrapArgs{
        .zig = try allocator.dupe(u8, zig),
        .deps = deps.items,
    };
}

const RunnerArgs = struct {
    target: []const u8,
    args: [][]const u8,
};
pub fn parseRunner() !RunnerArgs {
    const params = comptime clap.parseParamsComptime(
        \\-t, --target <str>  An option parameter which can be specified multiple times.
        \\-a, --args <str>  An option parameter which can be specified multiple times.
        \\<str>...
        \\
    );

    const allocator = std.heap.page_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const target: []const u8 = res.args.target orelse "";
    const raw_args: []const u8 = res.args.args orelse "";

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 3);
    var args_split = std.mem.splitScalar(u8, raw_args, ' ');
    while (args_split.next()) |a| {
        const arg = std.mem.trim(u8, a, " ");
        if (arg.len == 0) continue;
        try args.append(allocator, try allocator.dupe(u8, arg));
    }

    return RunnerArgs{
        .target = try allocator.dupe(u8, target),
        .args = args.items,
    };
}
