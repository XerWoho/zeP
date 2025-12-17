const std = @import("std");
const clap = @import("clap");

const DoctorArgs = struct {
    fix: bool,
};
pub fn parseDoctor(
    iter: *std.process.ArgIterator,
) !DoctorArgs {
    const params = [_]clap.Param(u8){
        .{
            .id = 'f',
            .names = .{ .short = 'f', .long = "fix" },
            .takes_value = .none,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var fix: bool = false;
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (true) {
        const arg = parser.next() catch break;
        if (arg == null) break;

        switch (arg.?.param.id) {
            'f' => {
                fix = true;
            },
            else => continue,
        }
    }

    return DoctorArgs{
        .fix = fix,
    };
}

const InstallArgs = struct {
    inj: bool,
};
pub fn parseInstall(
    iter: *std.process.ArgIterator,
) !InstallArgs {
    const params = [_]clap.Param(u8){
        .{
            .id = 'i',
            .names = .{ .short = 'i', .long = "inj" },
            .takes_value = .none,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var inj: bool = false;
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (true) {
        const arg = parser.next() catch break;
        if (arg == null) break;

        switch (arg.?.param.id) {
            'i' => inj = true,
            else => {},
        }
    }

    return InstallArgs{
        .inj = inj,
    };
}

const BootstrapArgs = struct {
    zig: []const u8,
    deps: [][]const u8,

    pub fn deinit(self: *BootstrapArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.zig);
        for (self.deps) |dep| {
            allocator.free(dep);
        }
    }
};
pub fn parseBootstrap(
    allocator: std.mem.Allocator,
    iter: *std.process.ArgIterator,
) !BootstrapArgs {
    const params = [_]clap.Param(u8){
        .{
            .id = 'z',
            .names = .{ .short = 'z', .long = "zig" },
            .takes_value = .one,
        },
        .{
            .id = 'd',
            .names = .{ .short = 'd', .long = "deps" },
            .takes_value = .one,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var zig: []const u8 = "0.14.0";
    var raw_deps: []const u8 = "";
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (true) {
        const arg = parser.next() catch break;
        if (arg == null) break;

        switch (arg.?.param.id) {
            'z' => {
                zig = arg.?.value orelse "";
            },
            'd' => {
                raw_deps = arg.?.value orelse "";
            },
            else => continue,
        }
    }

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

    pub fn deinit(self: *RunnerArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.target);
        for (self.args) |arg| {
            allocator.free(arg);
        }
    }
};
pub fn parseRunner(
    allocator: std.mem.Allocator,
    iter: *std.process.ArgIterator,
) !RunnerArgs {
    const params = [_]clap.Param(u8){
        .{
            .id = 't',
            .names = .{ .short = 't', .long = "target" },
            .takes_value = .one,
        },
        .{
            .id = 'a',
            .names = .{ .short = 'a', .long = "args" },
            .takes_value = .one,
        },
    };

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = iter,
        .diagnostic = &diag,
    };

    var target: []const u8 = "";
    var raw_args: []const u8 = "";
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (true) {
        const arg = parser.next() catch break;
        if (arg == null) break;

        switch (arg.?.param.id) {
            't' => {
                target = arg.?.value orelse "";
            },
            'a' => {
                raw_args = arg.?.value orelse "";
            },
            else => continue,
        }
    }

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
