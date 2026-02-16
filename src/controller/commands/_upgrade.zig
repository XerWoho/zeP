const std = @import("std");

const Upgrader = @import("../../lib/packages/upgrade.zig");

const Context = @import("context");
const Args = @import("args");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn upgrade(ctx: *Context) void {
    var upgade = Upgrader.init(ctx);
    upgade.upgrade() catch |err| CErrors.handleInstallableError(ctx, err, "Upgrading");
}

pub fn _upgradeController(ctx: *Context) !void {
    upgrade(ctx);
}
