const std = @import("std");
const Constants = @import("constants");

const parsedArgs = struct {
    options: [][]const u8,
    cmds: [][]const u8,
};

pub fn parseArgs(
    allocator: std.mem.Allocator,
    args: [][:0]u8,
) !parsedArgs {
    var options = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    var cmds = try std.ArrayList([]const u8).initCapacity(allocator, 3);

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            try options.append(allocator, arg);
            continue;
        }
        try cmds.append(allocator, arg);
    }

    defer options.deinit(allocator);
    defer cmds.deinit(allocator);

    const os = try allocator.dupe([]const u8, options.items);
    const cs = try allocator.dupe([]const u8, cmds.items);
    return parsedArgs{
        .options = os,
        .cmds = cs,
    };
}

const DefaultArgs = struct {
    verbosity: usize,
};
pub fn parseDefault(
    args: [][]const u8,
) DefaultArgs {
    var verbosity: usize = 1;
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--verbosity") and
            !std.mem.startsWith(u8, arg, "-V")) continue;
        var split = std.mem.splitAny(u8, arg, "=");
        _ = split.next();
        const val = split.next() orelse continue;

        const parsed = std.fmt.parseInt(u8, val, 10) catch 1;
        verbosity = parsed;
    }

    return DefaultArgs{
        .verbosity = verbosity,
    };
}

const DoctorArgs = struct {
    fix: bool,
};
pub fn parseDoctor(
    args: [][]const u8,
) DoctorArgs {
    var fix: bool = false;
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--fix") and
            !std.mem.startsWith(u8, arg, "-F")) continue;
        fix = true;
    }
    return DoctorArgs{
        .fix = fix,
    };
}

const UninstallArgs = struct {
    global: bool,
    force: bool,
};
pub fn parseUninstall(
    args: [][]const u8,
) UninstallArgs {
    var global: bool = false;
    var force: bool = false;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--global") or
            std.mem.startsWith(u8, arg, "-G"))
        {
            global = true;
        }
        if (std.mem.startsWith(u8, arg, "--force") or
            std.mem.startsWith(u8, arg, "-F"))
        {
            force = true;
        }
    }

    return UninstallArgs{
        .global = global,
        .force = force,
    };
}

const InstallArgs = struct {
    inject: bool,
    binary: bool,
    zep: bool,
    github: bool,
    codeberg: bool,
    gitlab: bool,
    local: bool,
};
pub fn parseInstall(
    args: [][]const u8,
) InstallArgs {
    var inject: bool = false;
    var binary: bool = false;
    var zep: bool = false;
    var github: bool = false;
    var codeberg: bool = false;
    var gitlab: bool = false;
    var local: bool = false;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--inject") or
            std.mem.startsWith(u8, arg, "-I"))
        {
            inject = true;
        }
        if (std.mem.startsWith(u8, arg, "--binary") or
            std.mem.startsWith(u8, arg, "-B"))
        {
            binary = true;
        }
        if (std.mem.startsWith(u8, arg, "--zep") or
            std.mem.startsWith(u8, arg, "-Z"))
        {
            zep = true;
        }
        if (std.mem.startsWith(u8, arg, "--github") or
            std.mem.startsWith(u8, arg, "-GH"))
        {
            github = true;
        }
        if (std.mem.startsWith(u8, arg, "--codeberg") or
            std.mem.startsWith(u8, arg, "-CB"))
        {
            codeberg = true;
        }
        if (std.mem.startsWith(u8, arg, "--gitlab") or
            std.mem.startsWith(u8, arg, "-GL"))
        {
            gitlab = true;
        }
        if (std.mem.startsWith(u8, arg, "--local") or
            std.mem.startsWith(u8, arg, "-L"))
        {
            local = true;
        }
    }

    return InstallArgs{
        .inject = inject,
        .binary = binary,
        .zep = zep,
        .github = github,
        .codeberg = codeberg,
        .gitlab = gitlab,
        .local = local,
    };
}

const BootstrapArgs = struct {
    zig: []const u8,
    pkgs: []const u8,
};
pub fn parseBootstrap(
    args: [][]const u8,
) BootstrapArgs {
    var zig: []const u8 = "";
    var raw_packages: []const u8 = "";
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--zig") or
            !std.mem.startsWith(u8, arg, "-Z"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            zig = val;
        }
        if (!std.mem.startsWith(u8, arg, "--packages") or
            !std.mem.startsWith(u8, arg, "-P"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            raw_packages = val;
        }
    }

    return BootstrapArgs{
        .zig = zig,
        .pkgs = raw_packages,
    };
}

const BuilderArgs = struct {
    path: []const u8,
    zig_version: []const u8,
};
pub fn parseBuilder(args: [][]const u8) BuilderArgs {
    var path: []const u8 = ".";
    var zig_version: []const u8 = Constants.Default.zig_version;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--path") or
            std.mem.startsWith(u8, arg, "-P"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            path = val;
        } else if (std.mem.startsWith(u8, arg, "--zig") or
            std.mem.startsWith(u8, arg, "-Z"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            zig_version = val;
        }
    }

    return BuilderArgs{
        .path = path,
        .zig_version = zig_version,
    };
}

const RunnerArgs = struct {
    target: []const u8,
    args: []const u8,
};
pub fn parseRunner(args: [][]const u8) RunnerArgs {
    var target: []const u8 = "";
    var raw_args: []const u8 = "";
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "--target") or
            !std.mem.startsWith(u8, arg, "-T"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            target = val;
        }
        if (!std.mem.startsWith(u8, arg, "--args") or
            !std.mem.startsWith(u8, arg, "-A"))
        {
            var split = std.mem.splitAny(u8, arg, "=");
            _ = split.next();
            const val = split.next() orelse continue;
            raw_args = val;
        }
    }

    return RunnerArgs{
        .target = target,
        .args = raw_args,
    };
}
