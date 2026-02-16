const std = @import("std");

const Constants = @import("constants");
const Context = @import("context");
const Locales = @import("locales");

fn version(ctx: *Context) void {
    if (Locales.VERBOSITY_MODE <= 1) {
        ctx.printer.append(
            "{s}",
            .{Constants.Default.version},
            .{},
        );
    } else {
        ctx.printer.append(
            "{s}+{s}",
            .{ Constants.Default.version, Constants.Default.commit },
            .{},
        );
    }
}

pub fn _versionController(ctx: *Context) !void {
    version(ctx);
}
