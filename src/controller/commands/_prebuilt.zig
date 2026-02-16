const std = @import("std");

const PreBuilt = @import("../../lib/functions/pre_built.zig");
const Lister = @import("../../lib/packages/list.zig");

const Context = @import("context");
const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn prebuiltBuild(ctx: *Context, prebuilt: *PreBuilt) void {
    const name = ctx.cmds[3];
    const target = if (ctx.cmds.len < 5) "." else ctx.cmds[4];
    prebuilt.build(name, target) catch |err| CErrors.handlePreBuiltError(ctx, err, "Build");
}

fn prebuiltUse(ctx: *Context, prebuilt: *PreBuilt) void {
    const name = ctx.cmds[3];
    const target = if (ctx.cmds.len < 5) "." else ctx.cmds[4];
    prebuilt.use(name, target) catch |err| CErrors.handlePreBuiltError(ctx, err, "Use");
}

fn prebuiltList(ctx: *Context, prebuilt: *PreBuilt) void {
    prebuilt.list() catch |err| CErrors.handlePreBuiltError(ctx, err, "List");
}

fn prebuiltDelete(ctx: *Context, prebuilt: *PreBuilt) void {
    const name = ctx.cmds[3];
    prebuilt.delete(name) catch |err| CErrors.handlePreBuiltError(ctx, err, "Delete");
}

pub fn _prebuiltController(ctx: *Context) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.PreBuilt;

    var prebuilt = PreBuilt.init(ctx) catch return Errors.Controller.Main.Failed;

    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "build")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingSubcommand.PreBuilt;
        prebuiltBuild(ctx, &prebuilt);
    } else if (std.mem.eql(u8, arg, "delete")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingSubcommand.PreBuilt;
        prebuiltDelete(ctx, &prebuilt);
    } else if (std.mem.eql(u8, arg, "use")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingSubcommand.PreBuilt;
        prebuiltUse(ctx, &prebuilt);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        prebuiltList(ctx, &prebuilt);
    } else {
        return Errors.Controller.MissingSubcommand.PreBuilt;
    }
}
