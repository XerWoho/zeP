const std = @import("std");

const Release = @import("../../lib/cloud/release.zig");

const Context = @import("context");
const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn releaseCreate(ctx: *Context, release: *Release) void {
    release.create() catch |err| CErrors.handleCloudError(ctx, err, "Release Creating");
}

fn releaseList(ctx: *Context, release: *Release) void {
    release.list() catch |err| CErrors.handleCloudError(ctx, err, "Release Listing");
}

fn releaseDelete(ctx: *Context, release: *Release) void {
    release.delete() catch |err| CErrors.handleCloudError(ctx, err, "Release Deleting");
}

pub fn _releaseController(ctx: *Context) !void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Release;

    var release = Release.init(ctx);
    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "create")) {
        releaseCreate(ctx, &release);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        releaseList(ctx, &release);
    } else if (std.mem.eql(u8, arg, "delete")) {
        releaseDelete(ctx, &release);
    } else {
        return Errors.Controller.MissingSubcommand.Release;
    }
}
