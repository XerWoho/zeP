const std = @import("std");
const builtin = @import("builtin");
const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Setup = @import("cli").Setup;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;
const Package = @import("core").Package.Package;
const Json = @import("core").Json.Json;

const Init = @import("lib/packages/init.zig").Init;
const Installer = @import("lib/packages/install.zig").Installer;
const Uninstaller = @import("lib/packages/uninstall.zig").Uninstaller;
const Lister = @import("lib/packages/list.zig").Lister;
const Purger = @import("lib/packages/purge.zig").Purger;
const CustomPackage = @import("lib/packages/custom.zig").CustomPackage;
const PreBuilt = @import("lib/functions/pre_built.zig").PreBuilt;
const Command = @import("lib/functions/command.zig").Command;
const PackageFiles = @import("lib/functions/package_files.zig").PackageFiles;
const Builder = @import("lib/functions/builder.zig").Builder;
const Runner = @import("lib/functions/runner.zig").Runner;
const Bootstrap = @import("lib/functions/bootstrap.zig");
const Doctor = @import("lib/functions/doctor.zig");

const Artifact = @import("lib/artifact/artifact.zig").Artifact;

const clap = @import("clap");

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
fn parseBootstrap(allocator: std.mem.Allocator) !BootstrapArgs {
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

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // skip .exe and command
    _ = iter.next();
    _ = iter.next();
    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    var zig: []const u8 = "0.14.0";
    var raw_deps: []const u8 = "";
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'z' => {
                zig = arg.value orelse "";
            },
            'd' => {
                raw_deps = arg.value orelse "";
            },
            else => continue,
        }
    }

    var deps = std.ArrayList([]const u8).init(allocator);
    var deps_split = std.mem.splitScalar(u8, raw_deps, ',');
    while (deps_split.next()) |d| {
        const dep = std.mem.trim(u8, d, " ");
        if (dep.len == 0) continue;
        try deps.append(try allocator.dupe(u8, dep));
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
fn parseRunner(allocator: std.mem.Allocator) !RunnerArgs {
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

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // skip .exe and command
    _ = iter.next();
    _ = iter.next();
    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    var target: []const u8 = "";
    var raw_args: []const u8 = "";
    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            't' => {
                target = arg.value orelse "";
            },
            'a' => {
                raw_args = arg.value orelse "";
            },
            else => continue,
        }
    }

    var args = std.ArrayList([]const u8).init(allocator);
    var args_split = std.mem.splitScalar(u8, raw_args, ' ');
    while (args_split.next()) |a| {
        const arg = std.mem.trim(u8, a, " ");
        if (arg.len == 0) continue;
        try args.append(try allocator.dupe(u8, arg));
    }

    return RunnerArgs{
        .target = try allocator.dupe(u8, target),
        .args = args.items,
    };
}

/// Print the usage and the legend of zeP.
fn printUsage(printer: *Printer) !void {
    try printer.append("\nUsage:\n", .{}, .{});
    try printer.append(" Legend:\n  > []  # required\n  > ()  # optional\n\n", .{}, .{});
    try printer.append("--- SIMPLE COMMANDS ---\n  zeP version\n  zeP help\n  zeP paths\n  zeP doctor\n\n", .{}, .{});
    try printer.append("--- BUILD COMMANDS ---\n  zeP runner (--target <target>) (--args <args>)\n  zeP build\n  zeP bootstrap (--zig <zig-version>) (--deps <package1,package2>)\n\n", .{}, .{});
    try printer.append("--- MANIFEST COMMANDS ---\n  zeP init\n  zeP lock\n  zeP json\n\n", .{}, .{});
    try printer.append("--- CMD COMMANDS ---\n  zeP cmd run [cmd]\n  zeP cmd add\n  zeP cmd remove <cmd>\n  zeP cmd list\n\n", .{}, .{});
    try printer.append("--- PACKAGE COMMANDS ---\n  zeP install (target)@(version)\n  zeP uninstall [target]\n", .{}, .{});
    try printer.append("  zeP purge [pkg|cache]\n", .{}, .{});
    try printer.append("  zeP pkg list [target]\n  zeP pkg remove [custom package name]\n  zeP pkg add\n\n", .{}, .{});
    try printer.append("--- PREBUILT COMMANDS ---\n  zeP prebuilt [build|use] [name] (target)\n", .{}, .{});
    try printer.append("  zeP prebuilt delete [name]\n  zeP prebuilt list\n\n", .{}, .{});
    try printer.append("--- ZIG COMMANDS ---\n  zeP zig [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zeP zig install [version] (target)\n  zeP zig list\n\n", .{}, .{});
    try printer.append("--- ZEP COMMANDS ---\n  zeP zep [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zeP zep install [version] (target)\n  zeP zep list\n\n", .{}, .{});
}

/// Fetch the next argument or print an error and exit out of the process.
fn nextArg(args: *std.process.ArgIterator, printer: *Printer, usage_message: []const u8) ![]const u8 {
    return args.next() orelse blk: {
        try printer.append("Missing argument:\n{s}\n", .{usage_message}, .{});
        std.process.exit(1);
        break :blk "";
    };
}

/// Resolve default target if no target specified
fn resolveDefaultTarget() []const u8 {
    if (builtin.target.os.tag == .windows) return Constants.Default.default_targets.windows;
    return Constants.Default.default_targets.linux;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(allocator);

    defer args.deinit();
    _ = args.skip(); // skip program name

    const data = std.ArrayList(Structs.Extras.PrinterData).init(allocator);
    var printer = Printer.init(data, allocator);
    defer printer.deinit();
    try printer.append("\n", .{}, .{});

    const subcommand = args.next() orelse {
        std.debug.print("Missing subcommand!", .{});
        try printUsage(&printer);
        return;
    };

    if (std.mem.eql(u8, subcommand, "setup")) {
        try Setup.setup(allocator, &printer);
        return;
    }
    if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage(&printer);
        return;
    }
    if (std.mem.eql(u8, subcommand, "version")) {
        try printer.append("zeP Version 0.6\n\n", .{}, .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "paths")) {
        var paths = try Constants.Paths.paths(allocator);
        defer paths.deinit();
        try printer.append("\n--- ZEP PATHS ---\n\nBase: {s}\nCustom: {s}\nRoot: {s}\nPrebuilt: {s}\nZepped: {s}\nPackage-Manifest: {s}\nPackge-Root: {s}\nZep-Manifest: {s}\nZep-Root: {s}\nZig-Manifest: {s}\nZig-Root: {s}\n\n", .{
            paths.base,
            paths.custom,
            paths.root,
            paths.prebuilt,
            paths.zepped,

            paths.pkg_manifest,
            paths.pkg_root,

            paths.zep_manifest,
            paths.zep_root,

            paths.zig_manifest,
            paths.zig_root,
        }, .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "doctor")) {
        try Doctor.doctor(allocator, &printer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "bootstrap")) {
        var bootstrap_args = try parseBootstrap(allocator);
        defer bootstrap_args.deinit(allocator);

        try Bootstrap.bootstrap(allocator, &printer, bootstrap_args.zig, bootstrap_args.deps);
        return;
    }

    // First verify that we are in zeP project
    if (Fs.existsFile(Constants.Extras.package_files.lock) and
        Fs.existsFile(Constants.Extras.package_files.manifest) and
        Fs.existsDir(Constants.Extras.package_files.zep_folder))
    {
        const lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, allocator, Constants.Extras.package_files.lock);
        defer lock.deinit();
        if (lock.value.schema != Constants.Extras.package_files.lock_schema_version) {
            try printer.append("Lock file schema is NOT matching with zeP version.\nConsider removing them, and re-initing!\n", .{}, .{ .color = 31 });
            return;
        }
    }

    if (std.mem.eql(u8, subcommand, "pkg")) {
        const mode = try nextArg(&args, &printer, " > zeP pkg [command]");

        if (std.mem.eql(u8, mode, "add")) {
            var custom = CustomPackage.init(allocator, &printer);
            try custom.requestPackage();
            return;
        }
        if (std.mem.eql(u8, mode, "remove")) {
            const target = args.next();
            var custom = CustomPackage.init(allocator, &printer);
            if (target == null) {
                try printer.append("No target specified!\n\n", .{}, .{});
                return;
            }
            try custom.removePackage(target.?);
            return;
        }

        if (std.mem.eql(u8, mode, "list")) {
            const target = args.next();
            if (target) |package| {
                var split = std.mem.splitScalar(u8, package, '@');
                const package_name = split.first();
                var lister = try Lister.init(allocator, &printer, package_name);
                lister.list() catch {
                    try printer.append("\nListing {s} has failed...\n\n", .{package_name}, .{ .color = 31 });
                };
            } else {
                try printer.append("Missing argument;\nzeP list [target]\n\n", .{}, .{ .color = 31 });
            }
            return;
        }
    }

    if (std.mem.eql(u8, subcommand, "init")) {
        var initter = try Init.init(allocator, &printer, false);
        try initter.commitInit();
        return;
    }

    if (std.mem.eql(u8, subcommand, "build")) {
        var builder = try Builder.init(allocator, &printer);
        const t = try builder.build();
        t.deinit();
        return;
    }

    if (std.mem.eql(u8, subcommand, "runner")) {
        var runner_args = try parseRunner(allocator);
        defer runner_args.deinit(allocator);

        var runner = try Runner.init(allocator, &printer);
        try runner.run(runner_args.target, runner_args.args);
        return;
    }

    if (std.mem.eql(u8, subcommand, "lock")) {
        var package_files = PackageFiles.init(allocator, &printer) catch |err| {
            switch (err) {
                error.ManifestMissing => {
                    try printer.append("zep.json manifest is missing!\n $ zeP init\nto get started!\n\n", .{}, .{ .color = 31 });
                    return;
                },
                else => {
                    try printer.append("Moving zep.json failed!\n\n", .{}, .{ .color = 31 });
                    return;
                },
            }
        };
        try package_files.lock();
        return;
    }

    if (std.mem.eql(u8, subcommand, "json")) {
        var package_files = PackageFiles.init(allocator, &printer) catch |err| {
            switch (err) {
                error.ManifestMissing => {
                    try printer.append("zep.json manifest is missing!\n $ zeP init\nto get started!\n\n", .{}, .{ .color = 31 });
                    return;
                },
                else => {
                    try printer.append("Moving zep.json failed!\n\n", .{}, .{ .color = 31 });
                    return;
                },
            }
        };
        try package_files.json();
        return;
    }

    if (std.mem.eql(u8, subcommand, "install")) {
        const target = args.next();
        if (target) |package| {
            var split = std.mem.splitScalar(u8, package, '@');
            const package_name = split.first();
            const package_version = split.next();

            var installer = try Installer.init(allocator, &printer, package_name, package_version);
            defer installer.deinit();
            installer.install() catch |err| {
                switch (err) {
                    error.AlreadyInstalled => {
                        try printer.append("\nAlready installed!\n\n", .{}, .{ .color = 33 });
                    },
                    error.HashMismatch => {
                        try printer.append("\nHASH MISMATCH!\nPLEASE REPORT!\n\n", .{}, .{ .color = 31 });
                    },
                    else => {
                        try printer.append("\nInstalling {s} has failed...\n\n", .{package}, .{ .color = 31 });
                    },
                }
            };
        } else {
            var installer = try Installer.init(allocator, &printer, null, null);
            defer installer.deinit();
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "uninstall")) {
        const target = try nextArg(&args, &printer, " > zeP uninstall [target]");
        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();

        var uninstaller = Uninstaller.init(allocator, package_name, &printer) catch |err| {
            switch (err) {
                error.NotInstalled => {
                    try printer.append("{s} is not installed!\n", .{package_name}, .{ .color = 31 });
                    try printer.append("(locally) => If you wanna uninstall it globally, use\n $ zep global-uninstall {s}@<version>\n\n", .{package_name}, .{ .color = 34 });
                },
                else => {
                    try printer.append("\nUninstalling {s} has failed...\n\n", .{package_name}, .{ .color = 31 });
                },
            }
            return;
        };
        defer uninstaller.deinit();
        uninstaller.uninstall() catch {
            try printer.append("\nUninstalling {s} has failed...\n\n", .{package_name}, .{ .color = 31 });
        };
        return;
    }

    if (std.mem.eql(u8, subcommand, "global-uninstall")) {
        const target = try nextArg(&args, &printer, " > zeP global-uninstall [target]@[version]");
        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();
        const package_version = split.next() orelse {
            try printer.append("\nVersion is required for global uninstalls.\n\n", .{}, .{ .color = 31 });
            return;
        };
        try printer.append("\nNon-Force global uninstalling {s}@{s}...\n", .{ package_name, package_version }, .{ .color = 34 });

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        var package = Package.init(allocator, package_name, package_version, &printer) catch |err| {
            switch (err) {
                error.PackageNotFound => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
                error.PackageVersion => {
                    try printer.append("\nPackage version not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
                else => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
            }
        };
        Locales.VERBOSITY_MODE = previous_verbosity;

        package.deletePackage(false) catch {
            try printer.append("\nDeleting failed.\n\n", .{}, .{ .color = 31 });
            return;
        };
        return;
    }

    if (std.mem.eql(u8, subcommand, "fglobal-uninstall")) {
        const target = try nextArg(&args, &printer, " > zeP global-uninstall [target]@[version]");
        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();

        const package_version = split.next() orelse {
            try printer.append("\nVersion is required for global uninstalls.\n\n", .{}, .{ .color = 31 });
            return;
        };
        try printer.append("\nForce global uninstalling {s}@{s}...\n", .{ package_name, package_version }, .{ .color = 34 });

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        var package = Package.init(allocator, package_name, package_version, &printer) catch |err| {
            switch (err) {
                error.PackageNotFound => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
                error.PackageVersion => {
                    try printer.append("\nPackage version not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
                else => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = 31 });
                    return;
                },
            }
        };
        Locales.VERBOSITY_MODE = previous_verbosity;

        package.deletePackage(true) catch {
            try printer.append("\nDeleting failed.\n\n", .{}, .{ .color = 31 });
            return;
        };
        try printer.append("\nPackage deleted, consequences ignored.\n\n", .{}, .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "purge")) {
        const mode = try nextArg(&args, &printer, " > zeP purge [pkg|cache]");
        var purger = try Purger.init(allocator, &printer);
        if (std.mem.eql(u8, mode, "pkg")) {
            purger.purgePkgs() catch {
                try printer.append("\nPurging packages has failed...\n\n", .{}, .{ .color = 31 });
            };
        } else if (std.mem.eql(u8, mode, "cache")) {
            purger.purgeCache() catch {
                try printer.append("\nPurging cache has failed...\n\n", .{}, .{ .color = 31 });
            };
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "prebuilt")) {
        const mode = try nextArg(&args, &printer, " > zeP prebuilt [build|use|delete] [name]");
        var prebuilt = try PreBuilt.init(allocator, &printer);

        if (std.mem.eql(u8, mode, "build") or std.mem.eql(u8, mode, "use")) {
            const name = try nextArg(&args, &printer, " > zeP prebuilt {build|use} [name] [target?]");
            const target = args.next() orelse blk: {
                try printer.append("No target specified! Rolling back to default \".\"\n\n", .{}, .{});
                break :blk ".";
            };
            if (std.mem.eql(u8, mode, "build")) {
                prebuilt.build(name, target) catch {
                    try printer.append("\nBuilding prebuilt has failed...\n\n", .{}, .{ .color = 31 });
                };
            } else {
                prebuilt.use(name, target) catch {
                    try printer.append("\nUsing prebuilt has failed...\n\n", .{}, .{ .color = 31 });
                };
            }
        } else if (std.mem.eql(u8, mode, "delete")) {
            const name = try nextArg(&args, &printer, " > zeP prebuilt delete [name]");
            prebuilt.delete(name) catch {
                try printer.append("\nDeleting prebuilt has failed...\n\n", .{}, .{ .color = 31 });
            };
        } else if (std.mem.eql(u8, mode, "list")) {
            try prebuilt.list();
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "zig")) {
        const mode = try nextArg(&args, &printer, " > zeP zig [install|switch|uninstall|list] [version]");
        var zig = try Artifact.init(allocator, &printer, .zig);
        defer zig.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zeP zig {install|switch|uninstall} [version] [target?]");
            const target = args.next() orelse resolveDefaultTarget();
            if (std.mem.eql(u8, mode, "install")) {
                zig.install(version, target) catch |err| {
                    switch (err) {
                        error.NotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = 31 });
                        },
                        else => {
                            try printer.append("\nInstalling zig version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                        },
                    }
                };
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                zig.uninstall(version, target) catch {
                    try printer.append("\nUninstalling zig version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                };
            } else {
                zig.switchVersion(version, target) catch |err| {
                    switch (err) {
                        error.NotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = 31 });
                        },
                        else => {
                            try printer.append("\nSwitching zig version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                        },
                    }
                };
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            zig.list() catch {
                try printer.append("\nListing zig versions has failed...\n\n", .{}, .{ .color = 31 });
            };
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "zep")) {
        const mode = try nextArg(&args, &printer, " > zeP zep [install|switch|uninstall|list] [version]");
        var zep = try Artifact.init(allocator, &printer, .zep);
        defer zep.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zeP zep {install|switch|uninstall} [version]");
            const target = args.next() orelse resolveDefaultTarget();

            if (std.mem.eql(u8, mode, "install")) {
                zep.install(version, target) catch |err| {
                    switch (err) {
                        error.NotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = 31 });
                        },
                        else => {
                            try printer.append("\nInstalling zep version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                        },
                    }
                };
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                zep.uninstall(version, target) catch {
                    try printer.append("\nUninstalling zep version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                };
            } else {
                zep.switchVersion(version, target) catch |err| {
                    switch (err) {
                        error.NotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = 31 });
                        },
                        else => {
                            try printer.append("\nSwitching zep version {s} has failed...\n\n", .{version}, .{ .color = 31 });
                        },
                    }
                };
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            try zep.list();
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "cmd")) {
        const mode = try nextArg(&args, &printer, " > zeP cmd [run|add|remove|list] <cmd>");
        var commander = Command.init(allocator, &printer) catch |err| {
            switch (err) {
                error.ManifestNotFound => {
                    try printer.append("zep.json manifest was not found!\n\n", .{}, .{ .color = 31 });
                    return;
                },
                else => {
                    try printer.append("Commander initing failed!\n\n", .{}, .{ .color = 31 });
                    return;
                },
            }
        };

        if (std.mem.eql(u8, mode, "run")) {
            const cmd = try nextArg(&args, &printer, " > zeP cmd add");
            try commander.run(cmd);
        }
        if (std.mem.eql(u8, mode, "add")) {
            try commander.add();
        }
        if (std.mem.eql(u8, mode, "remove")) {
            const cmd = try nextArg(&args, &printer, " > zeP cmd remove [cmd]");
            try commander.remove(cmd);
        }
        if (std.mem.eql(u8, mode, "list")) {
            try commander.list();
        }

        return;
    }

    // If we reach here, subcommand is invalid
    try printer.append("Invalid subcommand: {s}\n $ zeP help\n\nTo get the full list.\n\n", .{subcommand}, .{});
}
