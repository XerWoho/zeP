const std = @import("std");

const Cmd = @import("../../lib/functions/command.zig");
const Context = @import("context");

fn cmdRun(ctx: *Context, cmd: *Cmd) !void {
    const cmd_name = ctx.args[3];
    try cmd.run(cmd_name);
    return;
}

fn cmdAdd(ctx: *Context, cmd: *Cmd) !void {
    _ = ctx;
    try cmd.add();
    return;
}

fn cmdRemove(ctx: *Context, cmd: *Cmd) !void {
    const cmd_name = ctx.args[3];
    try cmd.remove(cmd_name);
    return;
}

fn cmdList(ctx: *Context, cmd: *Cmd) !void {
    _ = ctx;
    try cmd.list();
    return;
}

pub fn _cmdController(ctx: *Context) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var cmd = try Cmd.init(ctx);

    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "run"))
        try cmdRun(ctx, &cmd);
    if (std.mem.eql(u8, arg, "add"))
        try cmdAdd(ctx, &cmd);
    if (std.mem.eql(u8, arg, "remove"))
        try cmdRemove(ctx, &cmd);
    if (std.mem.eql(u8, arg, "list") or
        std.mem.eql(u8, arg, "ls"))
        try cmdList(ctx, &cmd);
}
