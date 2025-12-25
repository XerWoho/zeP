const std = @import("std");

const Project = @import("../../lib/cloud/project.zig").Project;

const Context = @import("context").Context;
fn projectCreate(ctx: *Context, project: *Project) !void {
    _ = ctx;
    try project.create();
    return;
}

fn projectList(ctx: *Context, project: *Project) !void {
    _ = ctx;
    try project.list();
    return;
}

fn projectDelete(ctx: *Context, project: *Project) !void {
    _ = ctx;
    try project.delete();
    return;
}

pub fn _projectController(
    ctx: *Context,
) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var project = Project.init(ctx);

    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "create"))
        try projectCreate(ctx, &project);

    if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls"))
        try projectDelete(ctx, &project);

    if (std.mem.eql(u8, arg, "delete"))
        try projectDelete(ctx, &project);
}
