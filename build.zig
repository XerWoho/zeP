const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zeP",
        .root_module = exe_mod,
    });

    const localesMod = b.createModule(.{
        .root_source_file = b.path("src/locales.zig"),
    });
    exe.root_module.addImport("locales", localesMod);

    const constantsMod = b.createModule(.{
        .root_source_file = b.path("src/constants.zig"),
    });
    exe.root_module.addImport("constants", constantsMod);

    const structsMod = b.createModule(.{
        .root_source_file = b.path("src/structs.zig"),
    });
    exe.root_module.addImport("structs", structsMod);

    const utilsMod = b.createModule(.{ .root_source_file = b.path("src/utils.zig"), .imports = &.{
        std.Build.Module.Import{ .name = "structs", .module = structsMod },
        std.Build.Module.Import{ .name = "constants", .module = constantsMod },
        std.Build.Module.Import{ .name = "locales", .module = localesMod },
    } });
    exe.root_module.addImport("utils", utilsMod);
    const libMod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
    });
    exe.root_module.addImport("lib", libMod);
    b.install_prefix = "C:/Users/Public/AppData/Local/zeP";
    @import(".zep/inject.zig").injectExtraImports(b, exe);
    b.installArtifact(exe);
}
