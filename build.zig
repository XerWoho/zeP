const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const zeP_executeable_mod = builder.createModule(.{
        .root_source_file = builder.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zeP_executeable = builder.addExecutable(.{
        .name = "zep",
        .root_module = zeP_executeable_mod,
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

    zeP_executeable.root_module.addImport("locales", localesMod);
    zeP_executeable.root_module.addImport("constants", constantsMod);
    zeP_executeable.root_module.addImport("structs", structsMod);
    zeP_executeable.root_module.addImport("core", coresMod);
    zeP_executeable.root_module.addImport("io", iosMod);
    zeP_executeable.root_module.addImport("cli", clisMod);

    @import(".zep/injector.zig").injectExtraImports(builder, zeP_executeable);
    builder.installArtifact(zeP_executeable);
}
