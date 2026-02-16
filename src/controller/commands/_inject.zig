const std = @import("std");

const Injector = @import("core").Injector;

const Context = @import("context");
const Errors = @import("errors");

fn inject(ctx: *Context) !void {
    var injector = Injector.init(
        ctx.allocator,
        ctx.manifest,
        &ctx.printer,
    );
    try injector.initInjector(true);
}

pub fn _injectController(ctx: *Context) Errors.Controller.Main!void {
    inject(ctx) catch return Errors.Controller.Main.Failed;
}
