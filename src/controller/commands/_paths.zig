const std = @import("std");
const Context = @import("context");

fn paths(ctx: *Context) void {
    ctx.printer.append("Paths:\n\nBase: {s}\nCustom: {s}\nPrebuilt: {s}\ncached: {s}\nPackage-Manifest: {s}\nPackge-Root: {s}\nzep-Manifest: {s}\nzep-Root: {s}\nZig-Manifest: {s}\nZig-Root: {s}\n\n", .{
        ctx.paths.base,
        ctx.paths.custom,
        ctx.paths.prebuilt,
        ctx.paths.cached,

        ctx.paths.pkg_manifest,
        ctx.paths.pkg_root,

        ctx.paths.zep_manifest,
        ctx.paths.zep_root,

        ctx.paths.zig_manifest,
        ctx.paths.zig_root,
    }, .{});
}

pub fn _pathsController(ctx: *Context) !void {
    paths(ctx);
}
