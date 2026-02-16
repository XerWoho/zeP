const std = @import("std");

const Package = @import("../../lib/cloud/package.zig");

const Context = @import("context");
const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn packageCreate(ctx: *Context, package: *Package) void {
    package.create() catch |err| CErrors.handleCloudError(ctx, err, "Package Creating");
}

fn packageList(ctx: *Context, package: *Package) void {
    package.list() catch |err| CErrors.handleCloudError(ctx, err, "Package Listing");
}

fn packageDelete(ctx: *Context, package: *Package) void {
    package.delete() catch |err| CErrors.handleCloudError(ctx, err, "Package Deleting");
}

pub fn _packageController(ctx: *Context) !void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Package;

    var package = Package.init(ctx);
    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "create")) {
        packageCreate(ctx, &package);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        packageList(ctx, &package);
    } else if (std.mem.eql(u8, arg, "delete")) {
        packageDelete(ctx, &package);
    } else {
        return Errors.Controller.MissingSubcommand.Package;
    }
}
