const std = @import("std");

const PreBuilt = @import("../../lib/functions/pre_built.zig").PreBuilt;
const Lister = @import("../../lib/packages/list.zig").Lister;

const Context = @import("context").Context;

fn prebuiltBuild(ctx: *Context, prebuilt: *PreBuilt) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    try ctx.logger.info("running prebuilt: build", @src());
    const name = ctx.args[3];
    const default_target = ".";
    const target = if (ctx.args.len < 5) default_target else ctx.args[4];
    try ctx.logger.infof("prebuilt build: name={s}", .{name}, @src());
    try ctx.logger.infof("prebuilt build: target={s}", .{name}, @src());
    prebuilt.build(name, target) catch {
        try ctx.printer.append("\nBuilding prebuilt has failed...\n\n", .{}, .{ .color = .red });
    };
    try ctx.logger.info("prebuilt build finished", @src());
    return;
}

fn prebuiltUse(ctx: *Context, prebuilt: *PreBuilt) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    try ctx.logger.info("running prebuilt: use", @src());
    const name = ctx.args[3];
    const default_target = ".";
    const target = if (ctx.args.len < 5) default_target else ctx.args[4];
    try ctx.logger.infof("prebuilt use: name={s}", .{name}, @src());
    try ctx.logger.infof("prebuilt use: target={s}", .{target}, @src());
    prebuilt.use(name, target) catch {
        try ctx.printer.append("\nUse prebuilt has failed...\n\n", .{}, .{ .color = .red });
    };
    try ctx.logger.info("prebuilt use finished", @src());
    return;
}

fn prebuiltList(ctx: *Context, prebuilt: *PreBuilt) !void {
    try ctx.logger.info("running prebuilt: list", @src());
    try prebuilt.list();
    try ctx.logger.info("prebuilt list finished", @src());
    return;
}

fn prebuiltDelete(ctx: *Context, prebuilt: *PreBuilt) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    try ctx.logger.info("running prebuilt: delete", @src());
    const name = ctx.args[3];
    try ctx.logger.infof("prebuilt delete: target={s}", .{name}, @src());

    prebuilt.delete(name) catch {
        try ctx.printer.append("\nDeleting prebuilt has failed...\n\n", .{}, .{ .color = .red });
    };
    try ctx.logger.info("prebuilt delete finished", @src());
    return;
}

pub fn _prebuiltController(
    ctx: *Context,
) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var prebuilt = try PreBuilt.init(ctx);

    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "build"))
        try prebuiltBuild(ctx, &prebuilt);

    if (std.mem.eql(u8, arg, "delete"))
        try prebuiltDelete(ctx, &prebuilt);

    if (std.mem.eql(u8, arg, "use"))
        try prebuiltUse(ctx, &prebuilt);

    if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls"))
        try prebuiltList(ctx, &prebuilt);
}
