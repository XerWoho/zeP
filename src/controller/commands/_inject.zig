const std = @import("std");

const Injector = @import("core").Injector;

const Context = @import("context");

fn inject(ctx: *Context) !void {
    try ctx.logger.info("running inject", @src());
    var injector = try Injector.init(
        ctx.allocator,
        &ctx.printer,
        &ctx.manifest,
        true,
    );
    try injector.initInjector();
    try ctx.logger.info("inject finished", @src());
    return;
}

pub fn _injectController(ctx: *Context) !void {
    try inject(ctx);
}
