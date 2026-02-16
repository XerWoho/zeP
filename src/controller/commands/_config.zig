const std = @import("std");

const PackageFiles = @import("../../lib/functions/package_files.zig");

const Context = @import("context");
const Errors = @import("errors");

fn config(_: *Context, pf: *PackageFiles) !void {
    try pf.modify();
}

pub fn _configController(ctx: *Context) Errors.Controller.Main!void {
    var package_files = PackageFiles.init(ctx);
    config(ctx, &package_files) catch return Errors.Controller.Main.Failed;
}
