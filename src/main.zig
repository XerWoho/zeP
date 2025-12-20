const std = @import("std");

const builtin = @import("builtin");
const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");
const Logger = @import("logger");

const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Setup = @import("cli").Setup;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;
const Package = @import("core").Package;
const Json = @import("core").Json;
const Injector = @import("core").Injector;

const Init = @import("lib/packages/init.zig").Init;
const Installer = @import("lib/packages/install.zig").Installer;
const Uninstaller = @import("lib/packages/uninstall.zig").Uninstaller;
const Lister = @import("lib/packages/list.zig").Lister;
const Purger = @import("lib/packages/purge.zig");
const CustomPackage = @import("lib/packages/custom.zig").CustomPackage;
const PreBuilt = @import("lib/functions/pre_built.zig").PreBuilt;
const Command = @import("lib/functions/command.zig").Command;
const PackageFiles = @import("lib/functions/package_files.zig").PackageFiles;
const Builder = @import("lib/functions/builder.zig").Builder;
const Runner = @import("lib/functions/runner.zig").Runner;
const Bootstrap = @import("lib/functions/bootstrap.zig");
const New = @import("lib/functions/new.zig");
const Doctor = @import("lib/functions/doctor.zig");
const Cache = @import("lib/functions/cache.zig").Cache;
const Artifact = @import("lib/artifact/artifact.zig").Artifact;

const Args = @import("args.zig");

/// Print the usage and the legend of zep.
fn printUsage(printer: *Printer) !void {
    try printer.append("\nUsage:\n", .{}, .{});
    try printer.append(" Legend:\n  > []  # required\n  > ()  # optional\n\n", .{}, .{});
    try printer.append("--- SIMPLE COMMANDS ---\n  zep version\n  zep help\n  zep paths\n  zep doctor\n\n", .{}, .{});
    try printer.append("--- BUILD COMMANDS ---\n  zep runner (--target <target>) (--args <args>)\n  zep build\n  zep bootstrap (--zig <zig-version>) (--deps <package1,package2>)\n  zep new <name>\n\n", .{}, .{});
    try printer.append("--- MANIFEST COMMANDS ---\n  zep init\n  zep lock\n  zep json\n\n", .{}, .{});
    try printer.append("--- CMD COMMANDS ---\n  zep cmd run [cmd]\n  zep cmd add\n  zep cmd remove <cmd>\n  zep cmd list\n\n", .{}, .{});
    try printer.append("--- PACKAGE COMMANDS ---\n  zep install (target)@(version)\n  zep uninstall [target]\n  zep info [target]@[version]\n", .{}, .{});
    try printer.append("  zep purge\n  zep cache [list|clean|size] (package_id)\n  zep inject\n", .{}, .{});
    try printer.append("  zep pkg list [target]\n  zep pkg remove [custom package name]\n  zep pkg add\n\n", .{}, .{});
    try printer.append("--- PREBUILT COMMANDS ---\n  zep prebuilt [build|use] [name] (target)\n", .{}, .{});
    try printer.append("  zep prebuilt delete [name]\n  zep prebuilt list\n\n", .{}, .{});
    try printer.append("--- ZIG COMMANDS ---\n  zep zig [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zep zig install [version] (target)\n  zep zig list\n  zep zig prune\n\n", .{}, .{});
    try printer.append("--- zep COMMANDS ---\n  zep zep [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zep zep install [version] (target)\n  zep zep list\n  zep zep prune\n\n", .{}, .{});
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
    const alloc = std.heap.page_allocator;
    var paths = try Constants.Paths.paths(alloc);
    defer paths.deinit();
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip(); // skip program name

    const log_file_identifier = try std.fmt.allocPrint(
        alloc,
        "{d}.log",
        .{
            std.time.milliTimestamp(),
        },
    );
    const log_location = try std.fs.path.join(alloc, &.{ paths.logs_root, log_file_identifier });
    defer {
        alloc.free(log_location);
        alloc.free(log_file_identifier);
    }

    try Logger.init(alloc, log_location);
    const logger = Logger.get();
    defer logger.deinit();
    defer {
        logger.flush() catch {
            @panic("flushing logger failed");
        };
    }
    try logger.debug("logger inited", @src());
    try logger.debugf("running zep={s}", .{Constants.Default.version}, @src());

    errdefer {
        std.debug.print("[ERR] Something failed. {s} - Report", .{log_location});
    }

    var printer = try Printer.init(alloc);
    defer printer.deinit();
    try printer.append("\n", .{}, .{});

    var json = try Json.init(alloc, &paths);
    var manifest = try Manifest.init(alloc, &json, &paths);

    const subcommand = args.next() orelse {
        std.debug.print("Missing subcommand!", .{});
        try printUsage(&printer);
        return;
    };
    try logger.infof("subcommand={s}", .{subcommand}, @src());

    const create_paths = [5][]const u8{
        paths.root,
        paths.zep_root,
        paths.zepped,
        paths.pkg_root,
        paths.zig_root,
    };

    var is_created = true;
    for (create_paths) |p| {
        is_created = Fs.existsDir(p);
        if (!is_created) break;
    }

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    defer arena_allocator.deinit();

    if (!is_created) {
        var stdin_buf: [100]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;

        try printer.append("\nNo setup detected. Run '$ zep setup'?\n", .{}, .{
            .color = .blue,
            .weight = .bold,
        });
        const answer = try Prompt.input(allocator, &printer, stdin, "(Y/n) > ", .{});
        if (answer.len == 0 or
            std.mem.startsWith(u8, answer, "y") or
            std.mem.startsWith(u8, answer, "Y"))
        {
            try Setup.setup(allocator, &printer, &paths);
        }
    }

    const zep_version_exists = Fs.existsFile(paths.zep_manifest);
    if (!zep_version_exists) {
        var stdin_buf: [100]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        try printer.append("\nzep appears to be running outside fitting directory. Run '$ zep zep install'?\n", .{}, .{});
        const answer = try Prompt.input(
            allocator,
            &printer,
            stdin,
            "(Y/n) > ",
            .{},
        );
        if (answer.len == 0 or
            std.mem.startsWith(u8, answer, "y") or
            std.mem.startsWith(u8, answer, "Y"))
        {
            var zep = try Artifact.init(
                allocator,
                &printer,
                &paths,
                &manifest,
                .zep,
            );
            defer zep.deinit();
            const target = resolveDefaultTarget();
            try zep.install("latest", target);
        }
    }

    if (std.mem.eql(u8, subcommand, "setup")) {
        try logger.info("running setup", @src());
        try Setup.setup(
            allocator,
            &printer,
            &paths,
        );
        try logger.info("setup finished", @src());
        return;
    }
    if (std.mem.eql(u8, subcommand, "help")) {
        try logger.info("running help", @src());
        try printUsage(&printer);
        try logger.info("help finished", @src());
        return;
    }
    if (std.mem.eql(u8, subcommand, "version")) {
        try printer.append("zep version {s}\n\n", .{Constants.Default.version}, .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "paths")) {
        try printer.append("\n--- ZEP PATHS ---\n\nBase: {s}\nCustom: {s}\nRoot: {s}\nPrebuilt: {s}\nzepped: {s}\nPackage-Manifest: {s}\nPackge-Root: {s}\nzep-Manifest: {s}\nzep-Root: {s}\nZig-Manifest: {s}\nZig-Root: {s}\n\n", .{
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
        try logger.info("running doctor", @src());
        const doctor_args = try Args.parseDoctor(&args);
        try Doctor.doctor(allocator, &printer, &manifest, doctor_args.fix);
        try logger.info("doctor finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "inject")) {
        try logger.info("running injector", @src());
        var injector = try Injector.init(
            allocator,
            &printer,
            &manifest,
            true,
        );
        try injector.initInjector();
        try logger.info("injector finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "bootstrap")) {
        try logger.info("running bootstrap", @src());
        var bootstrap_args = try Args.parseBootstrap(allocator, &args);
        defer bootstrap_args.deinit(allocator);

        try Bootstrap.bootstrap(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
            bootstrap_args.zig,
            bootstrap_args.deps,
        );
        try logger.info("bootstrap finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "new")) {
        try logger.info("running new", @src());
        const new_package_name = try nextArg(&args, &printer, " > zep new <name>");
        try New.new(
            allocator,
            &printer,
            new_package_name,
            &json,
        );

        try logger.info("new finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "cache")) {
        try logger.info("running cache", @src());

        const cache_subcommand = try nextArg(
            &args,
            &printer,
            " > zep cache [list|clean|size] (package_id)",
        );
        try logger.infof("running cache: subcommand={s}", .{cache_subcommand}, @src());
        var cache = try Cache.init(
            allocator,
            &printer,
            &paths,
        );
        defer cache.deinit();
        if (std.mem.eql(u8, cache_subcommand, "list") or std.mem.eql(u8, cache_subcommand, "ls")) {
            try logger.info("running cache list", @src());
            try cache.list();
            try logger.info("cache list finished", @src());
        } else if (std.mem.eql(u8, cache_subcommand, "clean")) {
            try logger.info("running cache clean", @src());
            const package_id = args.next();
            try cache.clean(package_id);
            try logger.info("cache clean finished", @src());
        } else if (std.mem.eql(u8, cache_subcommand, "size")) {
            try logger.info("running cache size", @src());
            try cache.size();
            try logger.info("cache size finished", @src());
        } else {
            try logger.warn("invalid cache mode", @src());
            try printer.append("Invalid mode: {s}\n\n", .{cache_subcommand}, .{});
        }
        try logger.info("cache finished", @src());
        return;
    }

    // First verify that we are in zep project
    if (Fs.existsFile(Constants.Extras.package_files.lock) and
        Fs.existsFile(Constants.Extras.package_files.manifest) and
        Fs.existsDir(Constants.Extras.package_files.zep_folder))
    {
        try logger.info("running within zep project", @src());
        const lock = try manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );
        defer lock.deinit();
        if (lock.value.schema != Constants.Extras.package_files.lock_schema_version) {
            try logger.warn("lockfile schema is not matching with zep version", @src());
            try printer.append("Lock file schema is NOT matching with zep version.\nConsider removing them, and re-initing!\n", .{}, .{ .color = .red });

            try Fs.deleteFileIfExists(Constants.Extras.package_files.lock);
            var package_files = try PackageFiles.init(
                allocator,
                &printer,
                &manifest,
            );
            try package_files.json();

            const prev_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;
            var installer = try Installer.init(
                allocator,
                &printer,
                &json,
                &paths,
                &manifest,
                false,
            );
            try installer.installAll();
            Locales.VERBOSITY_MODE = prev_verbosity;
            try logger.info("repaired zep.lock schema", @src());
            return;
        }
    }

    if (std.mem.eql(u8, subcommand, "pkg")) {
        try logger.info("running package", @src());
        const mode = try nextArg(&args, &printer, " > zep pkg [command]");
        try logger.infof("running package: subcommand={s}", .{mode}, @src());
        if (std.mem.eql(u8, mode, "add")) {
            try logger.info("running package: add", @src());
            var custom = CustomPackage.init(
                allocator,
                &printer,
                &paths,
            );
            try custom.requestPackage();
            try logger.info("running package: add finished", @src());
            return;
        }
        if (std.mem.eql(u8, mode, "remove")) {
            try logger.info("running package: remove", @src());
            const target = args.next() orelse {
                try printer.append("No target specified!\n\n", .{}, .{});
                return;
            };
            var custom = CustomPackage.init(
                allocator,
                &printer,
                &paths,
            );
            try custom.removePackage(target);
            try logger.info("running package: remove finished", @src());
            return;
        }

        if (std.mem.eql(u8, mode, "list")) {
            try logger.info("running package: list", @src());
            const target = args.next();
            if (target) |package| {
                var split = std.mem.splitScalar(u8, package, '@');
                const package_name = split.first();
                var lister = Lister.init(
                    allocator,
                    &printer,
                    &json,
                    package_name,
                );
                lister.list() catch |err| {
                    try logger.errf("running package: list failed, name={s} err={}", .{ package_name, err }, @src());
                    try printer.append("\nListing {s} has failed...\n\n", .{package_name}, .{ .color = .red });
                };
                try logger.info("running package: list finished", @src());
            } else {
                try logger.warn("missing target parameter", @src());
                try printer.append("Missing argument;\nzep list [target]\n\n", .{}, .{ .color = .red });
            }
            return;
        }
        try logger.info("package finished", @src());
    }

    if (std.mem.eql(u8, subcommand, "init")) {
        try logger.info("running init", @src());
        var initer = try Init.init(allocator, &printer, &json, false);
        try initer.commitInit();
        try logger.info("init finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "build")) {
        try logger.info("running build", @src());
        var builder = try Builder.init(
            allocator,
            &printer,
            &manifest,
        );
        var t = try builder.build();
        t.deinit(allocator);
        try logger.info("build finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "runner")) {
        try logger.info("running runner", @src());
        var runner_args = try Args.parseRunner(allocator, &args);
        defer runner_args.deinit(allocator);

        var runner = Runner.init(allocator, &printer, &manifest);
        try runner.run(runner_args.target, runner_args.args);
        try logger.info("runner finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "lock")) {
        try logger.info("running lock", @src());
        var package_files = PackageFiles.init(
            allocator,
            &printer,
            &manifest,
        ) catch |err| {
            try logger.infof("lock: moving failed, err={}", .{err}, @src());
            switch (err) {
                error.ManifestMissing => {
                    try printer.append("zep.json manifest is missing!\n $ zep init\nto get started!\n\n", .{}, .{ .color = .red });
                    return;
                },
                else => {
                    try printer.append("Moving zep.json failed!\n\n", .{}, .{ .color = .red });
                    return;
                },
            }
        };
        try logger.info("lock finished", @src());
        try package_files.lock();
        return;
    }

    if (std.mem.eql(u8, subcommand, "json")) {
        try logger.info("running json", @src());

        var package_files = PackageFiles.init(
            allocator,
            &printer,
            &manifest,
        ) catch |err| {
            try logger.infof("json: moving failed, err={}", .{err}, @src());
            switch (err) {
                error.ManifestMissing => {
                    try printer.append("zep.json manifest is missing!\n $ zep init\nto get started!\n\n", .{}, .{ .color = .red });
                    return;
                },
                else => {
                    try printer.append("Moving zep.json failed!\n\n", .{}, .{ .color = .red });
                    return;
                },
            }
        };
        try package_files.json();
        try logger.info("json finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "info")) {
        try logger.info("running info", @src());

        const target = try nextArg(&args, &printer, " > zep info [target]@[version]\n");
        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();
        const package_version = split.next() orelse {
            std.debug.print(" > zep info [target]@[version]\n", .{});
            std.debug.print("Version is required, when trying to info of package!\n", .{});
            return;
        };

        const package = try Package.init(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
            package_name,
            package_version,
        );
        std.debug.print("Package Name: {s}\n", .{package_name});
        std.debug.print("Version: {s}\n", .{package.package.version});
        std.debug.print("Sha256Sum: {s}\n", .{package.package.sha256sum});
        std.debug.print("Url: {s}\n", .{package.package.url});
        std.debug.print("Root File: {s}\n", .{package.package.root_file});
        std.debug.print("Zig Version: {s}\n", .{package.package.zig_version});
        std.debug.print("\n", .{});

        try logger.info("info finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "install")) {
        try logger.info("running install", @src());

        const target = args.next() orelse null;
        const install_args = try Args.parseInstall(&args);
        var installer = try Installer.init(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
            install_args.inj,
        );
        defer installer.deinit();

        if (target) |package| {
            try logger.infof("install: package={s}", .{package}, @src());
            var split = std.mem.splitScalar(u8, package, '@');
            const package_name = split.first();
            const package_version = split.next();
            installer.install(package_name, package_version) catch |err| {
                try logger.errf("install: failed, err={}", .{err}, @src());

                switch (err) {
                    error.AlreadyInstalled => {
                        try printer.append("\nAlready installed!\n\n", .{}, .{ .color = .yellow });
                    },
                    error.PackageNotFound => {
                        try printer.append("\nPackage not Found!\n\n", .{}, .{ .color = .yellow });
                    },
                    error.HashMismatch => {
                        try printer.append("  ! HASH MISMATCH!\nPLEASE REPORT!\n\n", .{}, .{ .color = .red });
                    },
                    else => {
                        try printer.append("\nInstalling {s} has failed...\n\n", .{package}, .{ .color = .red });
                    },
                }
            };
        } else {
            try logger.info("install: all", @src());
            installer.installAll() catch |err| {
                try logger.infof("install all: failed, err={}", .{err}, @src());
                switch (err) {
                    error.AlreadyInstalled => {
                        try printer.append("\nAlready installed!\n\n", .{}, .{ .color = .yellow });
                    },
                    error.HashMismatch => {
                        try printer.append("  ! HASH MISMATCH!\nPLEASE REPORT!\n\n", .{}, .{ .color = .red });
                    },
                    else => {
                        try printer.append("\nInstalling all has failed...\n\n", .{}, .{ .color = .red });
                    },
                }
            };
        }

        try logger.info("install: finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "uninstall")) {
        try logger.info("running uninstall", @src());

        const target = try nextArg(&args, &printer, " > zep uninstall [target]");
        try logger.infof("uninstall: target={s}", .{target}, @src());

        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();

        var uninstaller = Uninstaller.init(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
        ) catch |err| {
            try logger.errf("uninstall: failed, err={}", .{err}, @src());

            switch (err) {
                error.NotInstalled => {
                    try printer.append("{s} is not installed!\n", .{package_name}, .{ .color = .red });
                    try printer.append("(locally) => If you wanna uninstall it globally, use\n $ zep global-uninstall {s}@<version>\n\n", .{package_name}, .{ .color = .blue });
                },
                else => {
                    try printer.append("\nUninstalling {s} has failed...\n\n", .{package_name}, .{ .color = .red });
                },
            }
            return;
        };
        defer uninstaller.deinit();
        uninstaller.uninstall(package_name) catch |err| {
            try logger.errf("uninstall: failed, err={}", .{err}, @src());
            try printer.append("\nUninstalling {s} has failed...\n\n", .{package_name}, .{ .color = .red });
        };
        try logger.info("uninstall finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "global-uninstall")) {
        try logger.info("running global-uninstall", @src());
        const target = try nextArg(&args, &printer, " > zep global-uninstall [target]@[version]");
        var split = std.mem.splitScalar(u8, target, '@');
        try logger.infof("global-uninstall: target={s}", .{target}, @src());

        const package_name = split.first();
        const package_version = split.next() orelse {
            try printer.append("\nVersion is required for global uninstalls.\n\n", .{}, .{ .color = .red });
            return;
        };
        try printer.append("\nNon-Force global uninstalling {s}@{s}...\n", .{ package_name, package_version }, .{ .color = .blue });

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        var package = Package.init(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
            package_name,
            package_version,
        ) catch |err| {
            try logger.errf("global-uninstall: failed, err={}", .{err}, @src());

            switch (err) {
                error.PackageNotFound => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
                error.PackageVersion => {
                    try printer.append("\nPackage version not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
                else => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
            }
        };
        Locales.VERBOSITY_MODE = previous_verbosity;

        package.deletePackage(false) catch |err| {
            try logger.errf("global-uninstall: failed, err={}", .{err}, @src());
            try printer.append("\nDeleting failed.\n\n", .{}, .{ .color = .red });
            return;
        };
        try logger.info("global-uninstall finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "fglobal-uninstall")) {
        try logger.info("running fglobal-uninstall", @src());

        const target = try nextArg(&args, &printer, " > zep global-uninstall [target]@[version]");
        try logger.infof("fglobal-uninstall: target={s}", .{target}, @src());

        var split = std.mem.splitScalar(u8, target, '@');
        const package_name = split.first();

        const package_version = split.next() orelse {
            try printer.append("\nVersion is required for global uninstalls.\n\n", .{}, .{ .color = .red });
            return;
        };
        try printer.append("\nForce global uninstalling {s}@{s}...\n", .{ package_name, package_version }, .{ .color = .blue });

        const previous_verbosity = Locales.VERBOSITY_MODE;
        Locales.VERBOSITY_MODE = 0;
        var package = Package.init(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
            package_name,
            package_version,
        ) catch |err| {
            try logger.errf("fglobal-uninstall: failed, err={}", .{err}, @src());

            switch (err) {
                error.PackageNotFound => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
                error.PackageVersion => {
                    try printer.append("\nPackage version not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
                else => {
                    try printer.append("\nPackage not found.\n\n", .{}, .{ .color = .red });
                    return;
                },
            }
        };
        Locales.VERBOSITY_MODE = previous_verbosity;

        package.deletePackage(true) catch |err| {
            try logger.errf("fglobal-uninstall: failed, err={}", .{err}, @src());

            try printer.append("\nDeleting failed.\n\n", .{}, .{ .color = .red });
            return;
        };
        try logger.info("fglobal-uninstall finished", @src());
        try printer.append("\nPackage deleted, consequences ignored.\n\n", .{}, .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "purge")) {
        try logger.info("running purge", @src());

        try Purger.purge(
            allocator,
            &printer,
            &json,
            &paths,
            &manifest,
        );
        try logger.info("purge finished", @src());
        return;
    }

    if (std.mem.eql(u8, subcommand, "prebuilt")) {
        try logger.info("running prebuilt", @src());
        const mode = try nextArg(&args, &printer, " > zep prebuilt [build|use|delete] [name]");
        try logger.infof("prebuilt: subcommand={s}", .{mode}, @src());

        var prebuilt = try PreBuilt.init(
            allocator,
            &printer,
            &paths,
        );

        if (std.mem.eql(u8, mode, "build")) {
            try logger.info("running prebuilt: build", @src());
            const name = try nextArg(&args, &printer, " > zep prebuilt build [name] [target?]");
            const target = args.next() orelse blk: {
                try printer.append("No target specified! Rolling back to default \".\"\n\n", .{}, .{});
                break :blk ".";
            };
            try logger.infof("prebuilt build: name={s}", .{name}, @src());
            try logger.infof("prebuilt build: target={s}", .{name}, @src());
            prebuilt.build(name, target) catch {
                try printer.append("\nBuilding prebuilt has failed...\n\n", .{}, .{ .color = .red });
            };
            try logger.info("prebuilt build finished", @src());
        } else if (std.mem.eql(u8, mode, "use")) {
            try logger.info("running prebuilt: use", @src());
            const name = try nextArg(&args, &printer, " > zep prebuilt use [name] [target?]");
            const target = args.next() orelse blk: {
                try printer.append("No target specified! Rolling back to default \".\"\n\n", .{}, .{});
                break :blk ".";
            };
            try logger.infof("prebuilt use: name={s}", .{name}, @src());
            try logger.infof("prebuilt use: target={s}", .{name}, @src());
            prebuilt.use(name, target) catch {
                try printer.append("\nUse prebuilt has failed...\n\n", .{}, .{ .color = .red });
            };
            try logger.info("prebuilt use finished", @src());
        } else if (std.mem.eql(u8, mode, "delete")) {
            try logger.info("running prebuilt: delete", @src());
            const name = try nextArg(&args, &printer, " > zep prebuilt delete [name]");
            try logger.infof("prebuilt delete: target={s}", .{name}, @src());

            prebuilt.delete(name) catch {
                try printer.append("\nDeleting prebuilt has failed...\n\n", .{}, .{ .color = .red });
            };
            try logger.info("prebuilt delete finished", @src());
        } else if (std.mem.eql(u8, mode, "list")) {
            try logger.info("running prebuilt: list", @src());
            try prebuilt.list();
            try logger.info("prebuilt list finished", @src());
        } else {
            try logger.infof("invalid prebuilt mode={s}", .{mode}, @src());
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "zig")) {
        try logger.info("running zig", @src());

        const mode = try nextArg(&args, &printer, " > zep zig [install|switch|uninstall|list] [version]");
        try logger.infof("zig: mode={s}", .{mode}, @src());

        var zig = try Artifact.init(
            allocator,
            &printer,
            &paths,
            &manifest,
            .zig,
        );
        defer zig.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zep zig {install|switch|uninstall} [version] [target?]");
            const target = args.next() orelse resolveDefaultTarget();

            try logger.infof("running zig {s}: version={s} target={s}", .{ mode, version, target }, @src());

            if (std.mem.eql(u8, mode, "install")) {
                zig.install(version, target) catch |err| {
                    try logger.errf("zig install: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    try printer.append("ERR: {any}\n\n", .{err}, .{});
                    switch (err) {
                        error.VersionNotInstalled => {
                            try printer.append("\nVersion {s} is not installed...\n\n", .{version}, .{ .color = .red });
                        },
                        error.VersionNotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = .red });
                        },
                        error.VersionHasNoPath => {
                            try printer.append("\nVersion {s} has no given path...\n\n", .{version}, .{ .color = .red });
                        },
                        error.TarballNotFound => {
                            try printer.append("\nTarball for version {s} not found...\n\n", .{version}, .{ .color = .red });
                        },
                        else => {
                            try printer.append("\nInstalling zig version {s} has failed...\n\n", .{version}, .{ .color = .red });
                        },
                    }
                    return;
                };
                try logger.info("zig install: finished", @src());
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                zig.uninstall(version, target) catch |err| {
                    try logger.errf("zig uninstall: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    try printer.append("\nUninstalling zig version {s} has failed...\n\n", .{version}, .{ .color = .red });
                    return;
                };
                try logger.info("zig uninstall: finished", @src());
            } else {
                zig.switchVersion(version, target) catch |err| {
                    try logger.errf("zig switch: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    switch (err) {
                        error.VersionNotInstalled => {
                            try printer.append("\nVersion {s} is not installed...\n\n", .{version}, .{ .color = .red });
                        },
                        error.ManifestUpdateFailed => {
                            try printer.append("\nUpdating Manifest failed...\n\n", .{}, .{ .color = .red });
                        },
                        error.LockUpdateFailed => {
                            try printer.append("\nUpdating zep.lock failed...\n\n", .{}, .{ .color = .red });
                        },
                        error.JsonUpdateFailed => {
                            try printer.append("\nUpdating zep.json failed...\n\n", .{}, .{ .color = .red });
                        },
                        error.LinkUpdateFailed => {
                            try printer.append("\nUpdating symbolic link failed...\n\n", .{}, .{ .color = .red });
                        },
                        else => {
                            try printer.append("\nSwitching zig version {s} has failed...\n\n", .{version}, .{ .color = .red });
                        },
                    }
                    return;
                };
                try logger.info("zig switch: successful", @src());
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            zig.list() catch |err| {
                try logger.errf("zig list: failed, err={any}", .{err}, @src());
                switch (err) {
                    error.ManifestNotFound => {
                        try printer.append("\nManifest path is not defined! Use\n $ zep zig switch <zig-version>\nTo fix!\n", .{}, .{ .color = .red });
                    },
                    else => {
                        try printer.append("\nListing zig versions has failed...\n\n", .{}, .{ .color = .red });
                    },
                }
                return;
            };
            try logger.info("zig list finished", @src());
        } else if (std.mem.eql(u8, mode, "prune")) {
            try zig.prune();
            try logger.info("zig prune finished", @src());
        } else {
            try logger.errf("Invalid zig mode: {s}", .{mode}, @src());
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "zep")) {
        try logger.info("running zep", @src());

        const mode = try nextArg(&args, &printer, " > zep zep [install|switch|uninstall|list] [version]");
        try logger.infof("zep: mode={s}", .{mode}, @src());

        var zep = try Artifact.init(
            allocator,
            &printer,
            &paths,
            &manifest,
            .zep,
        );
        defer zep.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zep zep {install|switch|uninstall} [version]");
            const target = args.next() orelse resolveDefaultTarget();

            try logger.infof(
                "running: zep {s}, version={s} target={s}",
                .{ mode, version, target },
                @src(),
            );

            if (std.mem.eql(u8, mode, "install")) {
                zep.install(version, target) catch |err| {
                    try logger.errf("zep install: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    switch (err) {
                        error.VersionNotInstalled => {
                            try printer.append("\nVersion {s} is not installed...\n\n", .{version}, .{ .color = .red });
                        },
                        error.VersionNotFound => {
                            try printer.append("\nVersion {s} not found...\n\n", .{version}, .{ .color = .red });
                        },
                        error.VersionHasNoPath => {
                            try printer.append("\nVersion {s} has no given path...\n\n", .{version}, .{ .color = .red });
                        },
                        error.TarballNotFound => {
                            try printer.append("\nTarball for version {s} not found...\n\n", .{version}, .{ .color = .red });
                        },
                        else => {
                            try printer.append("\nInstalling zep version {s} has failed...\n\n", .{version}, .{ .color = .red });
                        },
                    }
                    return;
                };
                try logger.infof("zep install: finished, version={s} target={s}", .{ version, target }, @src());
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                zep.uninstall(version, target) catch |err| {
                    try logger.errf("zep uninstall: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    return;
                };
                try logger.infof("zep uninstall: finished, version={s} target={s}", .{ version, target }, @src());
            } else {
                zep.switchVersion(version, target) catch |err| {
                    try logger.errf("zep switch: failed, version={s} target={s} err={any}", .{ version, target, err }, @src());
                    switch (err) {
                        error.VersionNotInstalled => {
                            try printer.append("\nVersion {s} is not installed...\n\n", .{version}, .{ .color = .red });
                        },
                        error.ManifestUpdateFailed => {
                            try printer.append("\nUpdating Manifest failed...\n\n", .{}, .{ .color = .red });
                        },
                        error.LinkUpdateFailed => {
                            try printer.append("\nUpdating symbolic link failed...\n\n", .{}, .{ .color = .red });
                        },
                        else => {
                            try printer.append("\nSwitching zep version {s} has failed...\n\n", .{version}, .{ .color = .red });
                        },
                    }
                    return;
                };
                try logger.infof("zep switch: finished, version={s} target={s}", .{ version, target }, @src());
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            try logger.info("running zep list", @src());
            zep.list() catch |err| {
                try logger.errf("zep list: failed, err={any}", .{err}, @src());
                return;
            };
            try logger.info("zep list finished", @src());
        } else if (std.mem.eql(u8, mode, "prune")) {
            try logger.info("running zep prune", @src());
            try zep.prune();
            try logger.info("zep prune finished", @src());
        } else {
            try logger.errf("Invalid zep mode: {s}", .{mode}, @src());
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "cmd")) {
        try logger.info("running cmd", @src());

        const mode = try nextArg(&args, &printer, " > zep cmd [run|add|remove|list] <cmd>");
        try logger.infof("cmd: mode={s}", .{mode}, @src());

        var commander = Command.init(
            allocator,
            &printer,
            &manifest,
        ) catch |err| {
            try logger.errf("Commander init failed | err={any}", .{err}, @src());
            switch (err) {
                error.ManifestNotFound => {
                    try printer.append("zep.json manifest was not found!\n\n", .{}, .{ .color = .red });
                },
                else => {
                    try printer.append("Commander initing failed!\n\n", .{}, .{ .color = .red });
                },
            }
            return;
        };

        if (std.mem.eql(u8, mode, "run")) {
            const cmd = try nextArg(&args, &printer, " > zep cmd add");
            try logger.infof("running cmd run: cmd={s}", .{cmd}, @src());
            try commander.run(cmd);
            try logger.info("cmd run finished", @src());
        } else if (std.mem.eql(u8, mode, "add")) {
            try logger.info("running cmd add", @src());
            try commander.add();
            try logger.info("cmd add finished", @src());
        } else if (std.mem.eql(u8, mode, "remove")) {
            const cmd = try nextArg(&args, &printer, " > zep cmd remove [cmd]");
            try logger.infof("running cmd remove: cmd={s}", .{cmd}, @src());
            try commander.remove(cmd);
            try logger.info("cmd remove finished", @src());
        } else if (std.mem.eql(u8, mode, "list")) {
            try logger.info("running cmd list", @src());
            try commander.list();
            try logger.info("cmd list finished", @src());
        }
        try logger.info("cmd finished", @src());
        return;
    }

    // If we reach here, subcommand is invalid
    try printer.append("Invalid subcommand: {s}\n $ zep help\n\nTo get the full list.\n\n", .{subcommand}, .{});
}
