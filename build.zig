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
    const zep_executeable_mod_mod = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zep_executeable_mod = builder.addExecutable(.{
        .name = "zep",
        .root_module = zep_executeable_mod_mod,
    });

    const localesMod = builder.createModule(.{ .root_source_file = builder.path("src/locales.zig") });
    const constantsMod = builder.createModule(.{ .root_source_file = builder.path("src/constants/_index.zig") });
    const structsMod = builder.createModule(.{ .root_source_file = builder.path("src/structs/_index.zig"), .imports = &.{
        std.Build.Module.Import{ .name = "constants", .module = constantsMod },
    } });

    const iosMod = builder.createModule(.{ .root_source_file = builder.path("src/tools/io/_index.zig"), .imports = &.{
        std.Build.Module.Import{ .name = "constants", .module = constantsMod },
    } });
    const clisMod = builder.createModule(.{ .root_source_file = builder.path("src/tools/cli/_index.zig"), .imports = &.{
        std.Build.Module.Import{ .name = "structs", .module = structsMod },
        std.Build.Module.Import{ .name = "constants", .module = constantsMod },
        std.Build.Module.Import{ .name = "locales", .module = localesMod },
        std.Build.Module.Import{ .name = "io", .module = iosMod },
    } });

    const coresMod = builder.createModule(.{ .root_source_file = builder.path("src/tools/core/_index.zig"), .imports = &.{
        std.Build.Module.Import{ .name = "structs", .module = structsMod },
        std.Build.Module.Import{ .name = "locales", .module = localesMod },
        std.Build.Module.Import{ .name = "constants", .module = constantsMod },
        std.Build.Module.Import{ .name = "io", .module = iosMod },
        std.Build.Module.Import{ .name = "cli", .module = clisMod },
    } });
    coresMod.addIncludePath(.{
        .cwd_relative = "c/zstd/lib",
    });

    const zstd = builder.addStaticLibrary(.{
        .name = "zstd",
        .target = target,
        .optimize = optimize,
    });

    zstd.addIncludePath(.{
        .cwd_relative = "c/zstd/lib",
    });

    addCFilesFromDir(builder, zstd, "c/zstd/lib/common");
    addCFilesFromDir(builder, zstd, "c/zstd/lib/compress");
    addCFilesFromDir(builder, zstd, "c/zstd/lib/decompress");

    zstd.linkLibC();
    coresMod.linkLibrary(zstd);
    zep_executeable_mod.linkLibrary(zstd);
    zep_executeable_mod.linkLibC();

    zep_executeable_mod.root_module.addImport("locales", localesMod);
    zep_executeable_mod.root_module.addImport("constants", constantsMod);
    zep_executeable_mod.root_module.addImport("structs", structsMod);
    zep_executeable_mod.root_module.addImport("core", coresMod);
    zep_executeable_mod.root_module.addImport("io", iosMod);
    zep_executeable_mod.root_module.addImport("cli", clisMod);

    @import(".zep/injector.zig").injectExtraImports(builder, zep_executeable_mod);
    builder.installArtifact(zep_executeable_mod);
}
