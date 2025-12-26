const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");
const Logger = @import("logger");

const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Setup = @import("cli").Setup;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json;
const Fetch = @import("core").Fetch;
const Compressor = @import("core").Compressor;

const Installer = @import("lib/packages/install.zig");
const PackageFiles = @import("lib/functions/package_files.zig");
const Artifact = @import("lib/artifact/artifact.zig");

const Context = @import("context");

pub fn start(alloc: std.mem.Allocator) !Context {
    const args = try std.process.argsAlloc(alloc);

    const paths = try Constants.Paths.paths(alloc);
    const log_file_identifier = try std.fmt.allocPrint(
        alloc,
        "{d}.log",
        .{
            std.time.milliTimestamp(),
        },
    );
    const log_location = try std.fs.path.join(alloc, &.{ paths.logs_root, log_file_identifier });
    try Logger.init(alloc, log_location);
    const logger = Logger.get();

    var printer = try Printer.init(alloc);
    try printer.append("\n", .{}, .{});

    const json = Json.init(alloc, paths);
    var manifest = Manifest.init(alloc, json, paths);
    const fetcher = Fetch.init(alloc, json, paths);

    const compressor = Compressor.init(
        alloc,
        &printer,
        paths,
    );

    const create_paths = [5][]const u8{
        paths.root,
        paths.zep_root,
        paths.cached,
        paths.pkg_root,
        paths.zig_root,
    };

    var ctx = Context{
        .allocator = alloc,
        .fetcher = fetcher,
        .json = json,
        .logger = logger,
        .manifest = manifest,
        .paths = paths,
        .printer = printer,
        .compressor = compressor,
        .args = args,
    };

    var is_created = true;
    for (create_paths) |p| {
        is_created = Fs.existsDir(p);
        if (!is_created) break;
    }

    if (!is_created) {
        try printer.append("\nNo setup detected. Run '$ zep setup'?\n", .{}, .{
            .color = .blue,
            .weight = .bold,
        });

        const answer = try Prompt.input(
            alloc,
            &printer,
            "(Y/n) > ",
            .{},
        );
        if (answer.len == 0 or
            std.mem.startsWith(u8, answer, "y") or
            std.mem.startsWith(u8, answer, "Y"))
        {
            try Setup.setup(
                ctx.allocator,
                &ctx.paths,
                &ctx.printer,
            );
        }
    }

    const zep_version_exists = Fs.existsFile(paths.zep_manifest);
    if (!zep_version_exists) {
        try printer.append("\nzep appears to be running outside fitting directory. Run '$ zep zep install'?\n", .{}, .{});
        const answer = try Prompt.input(
            alloc,
            &printer,
            "(Y/n) > ",
            .{},
        );
        if (answer.len == 0 or
            std.mem.startsWith(u8, answer, "y") or
            std.mem.startsWith(u8, answer, "Y"))
        {
            var zep = try Artifact.init(
                &ctx,
                .zep,
            );
            defer zep.deinit();
            const target = Constants.Default.resolveDefaultTarget();
            try zep.install("latest", target);
        }
    }

    // First verify that we are in zep project
    if (Fs.existsFile(Constants.Extras.package_files.lock) and
        Fs.existsFile(Constants.Extras.package_files.manifest) and
        Fs.existsDir(Constants.Extras.package_files.zep_folder))
    {
        const lock = try manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );
        defer lock.deinit();
        if (lock.value.schema != Constants.Extras.package_files.lock_schema_version) {
            try printer.append("Lock file schema is NOT matching with zep version.\nAttempting to fix!\n", .{}, .{ .color = .red });

            try Fs.deleteFileIfExists(Constants.Extras.package_files.lock);
            var package_files = try PackageFiles.init(&ctx);
            try package_files.sync();

            const prev_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;
            var installer = Installer.init(&ctx);
            installer.install_unverified_packages = true;

            try installer.installAll();
            Locales.VERBOSITY_MODE = prev_verbosity;
            try printer.append("Fixed.\n\n", .{}, .{ .color = .green });
        }
    }

    return ctx;
}
