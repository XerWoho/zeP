const std = @import("std");

const Cmd = @import("../../lib/functions/command.zig");
const Context = @import("context");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn cmdRun(ctx: *Context, cmd: *Cmd) void {
    const cmd_name = ctx.cmds[3];
    cmd.run(cmd_name) catch |err| CErrors.handleCmdError(ctx, err, "run");
}

fn cmdAdd(ctx: *Context, cmd: *Cmd) void {
    cmd.add() catch |err| CErrors.handleCmdError(ctx, err, "add");
}

fn cmdRemove(ctx: *Context, cmd: *Cmd) void {
    const cmd_name = ctx.cmds[3];
    cmd.remove(cmd_name) catch |err| CErrors.handleCmdError(ctx, err, "remove");
}

fn cmdList(ctx: *Context, cmd: *Cmd) void {
    cmd.list() catch |err| CErrors.handleCmdError(ctx, err, "list");
}

pub fn _cmdController(ctx: *Context) !void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Cmd;

    var cmd = Cmd.init(ctx);

    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "run")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingSubcommand.Cmd;
        cmdRun(ctx, &cmd);
    } else if (std.mem.eql(u8, arg, "add")) {
        cmdAdd(ctx, &cmd);
    } else if (std.mem.eql(u8, arg, "remove")) {
        if (ctx.cmds.len < 4) return Errors.Controller.MissingSubcommand.Cmd;
        cmdRemove(ctx, &cmd);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        cmdList(ctx, &cmd);
    } else {
        return Errors.Controller.MissingSubcommand.Cmd;
    }
}
