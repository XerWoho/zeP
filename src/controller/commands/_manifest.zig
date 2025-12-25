const std = @import("std");

const PackageFiles = @import("../../lib/functions/package_files.zig");

const Context = @import("context");

fn manifestSync(ctx: *Context, pf: *PackageFiles) !void {
    try ctx.logger.info("running manifest", @src());
    try pf.sync();

    try ctx.logger.info("manifest finished", @src());
    return;
}

fn manifestModify(ctx: *Context, pf: *PackageFiles) !void {
    try ctx.logger.info("running manifest", @src());
    try pf.modify();
    try pf.sync();
    try ctx.logger.info("manifest finished", @src());
    return;
}

pub fn _manifestController(ctx: *Context) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var package_files = try PackageFiles.init(ctx);
    const arg = ctx.args[2];

    if (std.mem.eql(u8, arg, "sync"))
        try manifestSync(ctx, &package_files);

    if (std.mem.eql(u8, arg, "modify"))
        try manifestModify(ctx, &package_files);
}
