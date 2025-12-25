const std = @import("std");
const Context = @import("context");

fn paths(ctx: *Context) !void {
    try ctx.logger.info("running doctor", @src());

    try ctx.printer.append("\n--- ZEP PATHS ---\n\nBase: {s}\nCustom: {s}\nRoot: {s}\nPrebuilt: {s}\ncached: {s}\nPackage-Manifest: {s}\nPackge-Root: {s}\nzep-Manifest: {s}\nzep-Root: {s}\nZig-Manifest: {s}\nZig-Root: {s}\n\n", .{
        ctx.paths.base,
        ctx.paths.custom,
        ctx.paths.root,
        ctx.paths.prebuilt,
        ctx.paths.cached,

        ctx.paths.pkg_manifest,
        ctx.paths.pkg_root,

        ctx.paths.zep_manifest,
        ctx.paths.zep_root,

        ctx.paths.zig_manifest,
        ctx.paths.zig_root,
    }, .{});

    try ctx.logger.info("doctor finished", @src());
    return;
}

pub fn _pathsController(ctx: *Context) !void {
    try paths(ctx);
}
