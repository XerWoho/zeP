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
const Injector = @import("core").Injector;
const Args = @import("args");

const Installer = @import("lib/packages/install.zig");
const Artifact = @import("lib/artifact/artifact.zig");

const Context = @import("context");
const Migrate = @import("migrate.zig");

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

    try logger.info("Initializing zep...", @src());
    var printer = try Printer.init(alloc);

    var manifest = Manifest.init(
        alloc,
        paths,
    );
    const fetcher = Fetch.init(
        alloc,
        paths,
        manifest,
    );

    const compressor = Compressor.init(
        alloc,
        paths,
    );

    const parsed_args = try Args.parseArgs(alloc, args);
    const default = Args.parseDefault(parsed_args.options);
    Locales.VERBOSITY_MODE = @intCast(default.verbosity);

    const logger_wrapper = Logger.Wrapper.init(logger);
    var ctx = Context{
        .allocator = alloc,
        .fetcher = fetcher,
        .logger = logger_wrapper,
        .manifest = manifest,
        .paths = paths,
        .printer = printer,
        .compressor = compressor,
        .args = args,
        .cmds = parsed_args.cmds,
        .options = parsed_args.options,
    };
    try Migrate.migratePaths(&ctx);

    const create_paths = [7][]const u8{
        paths.base,
        paths.zep_root,
        paths.cached,
        paths.pkg_cached,
        paths.meta_cached,
        paths.pkg_root,
        paths.zig_root,
    };

    var is_created = true;
    for (create_paths) |p| {
        is_created = Fs.existsDir(p);
        if (!is_created) break;
    }

    if (!is_created) {
        try Setup.setup(
            ctx.allocator,
            &ctx.paths,
            &ctx.printer,
        );
    }

    const zep_version_exists = Fs.existsFile(paths.zep_manifest);
    if (!zep_version_exists) {
        printer.append("zep appears to be running outside fitting directory. Run '$ zep zep install'?\n", .{}, .{});
        const answer = try Prompt.input(
            alloc,
            &printer,
            "(Y/n) > ",
            .{},
        );
        if (answer.len == 0 or
            !std.mem.startsWith(u8, answer, "n") or
            !std.mem.startsWith(u8, answer, "N"))
        {
            try logger.info("Installing latest zep version...", @src());

            var zep = Artifact.init(
                &ctx,
                .zep,
            );
            defer zep.deinit();
            const target = Constants.Default.resolveDefaultTarget();
            try zep.install("latest", target);
        }
    }

    // First verify that we are in zep project
    if (Fs.existsFile(Constants.Default.package_files.lock)) {
        const lock = try manifest.readManifest(
            Structs.ZepFiles.Lock,
            Constants.Default.package_files.lock,
        );
        defer lock.deinit();
        if (lock.value.schema != Constants.Default.package_files.lock_schema_version) {
            try logger.info("Correcting Lock file...", @src());

            printer.append("Lock file schema is NOT matching with zep version.\nAttempting to fix!\n", .{}, .{ .color = .red });

            try Fs.deleteFileIfExists(Constants.Default.package_files.lock);
            const prev_verbosity = Locales.VERBOSITY_MODE;
            Locales.VERBOSITY_MODE = 0;

            var installer = Installer.init(&ctx);
            try installer.installAll();

            Locales.VERBOSITY_MODE = prev_verbosity;
            printer.append("Fixed.\n\n", .{}, .{ .color = .green });
        }
    }

    return ctx;
}
