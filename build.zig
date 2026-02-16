const __zepinj__ = @import(".zep/injector.zig");
const std = @import("std");

fn addCFilesFromDir(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    dir_path: []const u8,
) void {
    var dir = std.fs.cwd().openDir(dir_path, .{
        .iterate = true,
    }) catch unreachable;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch unreachable) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".c")) continue;

        const full = b.pathJoin(&.{ dir_path, entry.name });
        lib.addCSourceFile(
            .{
                .file = .{ .cwd_relative = full },
                .flags = &.{"-DZSTD_DISABLE_ASM"},
            },
        );
    }
}

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const zep_executeable_module = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    __zepinj__.imp(builder, zep_executeable_module);

    const zep_executeable = builder.addExecutable(.{
        .name = "zep",
        .root_module = zep_executeable_module,
    });

    const locales_mod = builder.createModule(.{ .root_source_file = builder.path("src/locales.zig") });
    const constants_mod = builder.createModule(.{ .root_source_file = builder.path("src/constants/_index.zig") });
    const errors_mod = builder.createModule(.{ .root_source_file = builder.path("src/errors.zig") });

    const loggers_mod = builder.createModule(.{ .root_source_file = builder.path("src/logger.zig") });
    __zepinj__.imp(builder, loggers_mod);
    loggers_mod.addImport("constants", constants_mod);

    const structs_mod = builder.createModule(.{ .root_source_file = builder.path("src/structs/_index.zig") });
    structs_mod.addImport("constants", constants_mod);

    const ios_mod = builder.createModule(.{ .root_source_file = builder.path("src/tools/io/_index.zig") });
    const clis_mod = builder.createModule(.{ .root_source_file = builder.path("src/tools/cli/_index.zig") });
    clis_mod.addImport("io", ios_mod);
    clis_mod.addImport("constants", constants_mod);
    clis_mod.addImport("locales", locales_mod);

    const cores_mod = builder.createModule(.{ .root_source_file = builder.path("src/tools/core/_index.zig") });
    __zepinj__.imp(builder, cores_mod);
    cores_mod.addImport("io", ios_mod);
    cores_mod.addImport("cli", clis_mod);
    cores_mod.addImport("constants", constants_mod);
    cores_mod.addImport("locales", locales_mod);
    cores_mod.addImport("structs", structs_mod);
    cores_mod.addImport("logger", loggers_mod);
    cores_mod.addImport("errors", errors_mod);

    cores_mod.addIncludePath(.{
        .cwd_relative = "vendor/zstd/lib",
    });

    const args_mod = builder.createModule(.{ .root_source_file = builder.path("src/args.zig") });
    args_mod.addImport("constants", constants_mod);

    const context_mod = builder.createModule(.{ .root_source_file = builder.path("src/context.zig") });
    __zepinj__.imp(builder, context_mod);
    context_mod.addImport("constants", constants_mod);
    context_mod.addImport("cli", clis_mod);
    context_mod.addImport("core", cores_mod);
    context_mod.addImport("logger", loggers_mod);
    context_mod.addImport("args", args_mod);

    const resolver_mod = builder.createModule(.{ .root_source_file = builder.path("src/resolver.zig") });
    resolver_mod.addImport("constants", constants_mod);
    resolver_mod.addImport("loggers", loggers_mod);
    resolver_mod.addImport("structs", structs_mod);
    resolver_mod.addImport("io", ios_mod);
    resolver_mod.addImport("cli", clis_mod);
    resolver_mod.addImport("core", cores_mod);
    resolver_mod.addImport("context", context_mod);
    resolver_mod.addImport("errors", errors_mod);

    const package_mod = builder.createModule(.{ .root_source_file = builder.path("src/package.zig") });
    __zepinj__.imp(builder, package_mod);
    package_mod.addImport("constants", constants_mod);
    package_mod.addImport("loggers", loggers_mod);
    package_mod.addImport("structs", structs_mod);
    package_mod.addImport("io", ios_mod);
    package_mod.addImport("cli", clis_mod);
    package_mod.addImport("core", cores_mod);
    package_mod.addImport("context", context_mod);
    package_mod.addImport("resolver", resolver_mod);
    package_mod.addImport("errors", errors_mod);

    const zstd = builder.addLibrary(.{
        .name = "zstd",
        .root_module = builder.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    zstd.addIncludePath(.{
        .cwd_relative = "vendor/zstd/lib",
    });

    addCFilesFromDir(builder, zstd, "vendor/zstd/lib/common");
    addCFilesFromDir(builder, zstd, "vendor/zstd/lib/compress");
    addCFilesFromDir(builder, zstd, "vendor/zstd/lib/decompress");

    zstd.linkLibC();
    cores_mod.linkLibrary(zstd);
    zep_executeable.linkLibrary(zstd);
    zep_executeable.linkLibC();

    zep_executeable_module.addImport("locales", locales_mod);
    zep_executeable_module.addImport("constants", constants_mod);
    zep_executeable_module.addImport("structs", structs_mod);
    zep_executeable_module.addImport("core", cores_mod);
    zep_executeable_module.addImport("io", ios_mod);
    zep_executeable_module.addImport("cli", clis_mod);
    zep_executeable_module.addImport("logger", loggers_mod);
    zep_executeable_module.addImport("context", context_mod);
    zep_executeable_module.addImport("args", args_mod);
    zep_executeable_module.addImport("package", package_mod);
    zep_executeable_module.addImport("resolver", resolver_mod);
    zep_executeable_module.addImport("errors", errors_mod);

    const testing_modules = [5]Modules{
        .{ .name = "constants", .module = constants_mod },
        .{ .name = "structs", .module = structs_mod },
        .{ .name = "cli", .module = clis_mod },
        .{ .name = "core", .module = cores_mod },
        .{ .name = "io", .module = ios_mod },
    };
    runTests(builder, target, &testing_modules);

    builder.installArtifact(zep_executeable);
}

const Modules = struct {
    name: []const u8,
    module: *std.Build.Module,
};

fn runTests(
    builder: *std.Build,
    target: std.Build.ResolvedTarget,
    modules: []const Modules,
) void {
    const zep_test_module = builder.createModule(.{
        .root_source_file = builder.path("tests/tests.zig"),
        .target = target,
    });
    for (modules) |m| {
        zep_test_module.addImport(m.name, m.module);
    }

    const zep_test = builder.addTest(.{
        .name = "test",
        .root_module = zep_test_module,
    });

    const run_tests = builder.addRunArtifact(zep_test);

    const test_step = builder.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
