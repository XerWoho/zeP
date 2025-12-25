const std = @import("std");

const Release = @import("../../lib/cloud/release.zig");

const Context = @import("context");
fn releaseCreate(ctx: *Context, release: *Release) !void {
    _ = ctx;
    try release.create();
    return;
}

fn releaseList(ctx: *Context, release: *Release) !void {
    _ = ctx;
    try release.list();
    return;
}

fn releaseDelete(ctx: *Context, release: *Release) !void {
    _ = ctx;
    try release.delete();
    return;
}

pub fn _releaseController(ctx: *Context) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var release = Release.init(ctx);
    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "create"))
        try releaseCreate(ctx, &release);

    if (std.mem.eql(u8, arg, "list") or
        std.mem.eql(u8, arg, "ls"))
        try releaseList(ctx, &release);

    if (std.mem.eql(u8, arg, "delete"))
        try releaseDelete(ctx, &release);
}
