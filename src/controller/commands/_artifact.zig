const std = @import("std");
const Structs = @import("structs");
const Constants = @import("constants");

const Artifact = @import("../../lib/artifact/artifact.zig");
const Context = @import("context");

fn artifactInstall(ctx: *Context, artifact: *Artifact) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    const target_version = ctx.args[3];
    const target = if (ctx.args.len < 5) Constants.Default.resolveDefaultTarget() else ctx.args[4];

    artifact.install(target_version, target) catch |err| {
        switch (err) {
            error.VersionNotFound => {
                try ctx.printer.append("Version {s} was not found.\n\n", .{target_version}, .{});
            },
            else => {
                try ctx.printer.append("Installing failed\n\n", .{}, .{});
            },
        }
    };
    return;
}

fn artifactUninstall(ctx: *Context, artifact: *Artifact) !void {
    if (ctx.args.len < 4) return error.MissingArguments;
    const target_version = ctx.args[3];
    const target = if (ctx.args.len < 5) Constants.Default.resolveDefaultTarget() else ctx.args[4];

    artifact.uninstall(target_version, target) catch |err| {
        switch (err) {
            error.VersionNotFound => {
                try ctx.printer.append("Version {s} was not found.\n\n", .{target_version}, .{});
            },
            error.VersionNotInstalled => {
                try ctx.printer.append("Version {s} is not installed.\n\n", .{target_version}, .{});
            },
            else => {
                try ctx.printer.append("Installing failed\n\n", .{}, .{});
            },
        }
    };
    return;
}

fn artifactSwitch(ctx: *Context, artifact: *Artifact) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    const target_version = ctx.args[3];
    const target = if (ctx.args.len < 5) Constants.Default.resolveDefaultTarget() else ctx.args[4];

    artifact.switchVersion(target_version, target) catch |err| {
        switch (err) {
            error.VersionNotFound => {
                try ctx.printer.append("Version {s} was not found.\n\n", .{target_version}, .{});
            },
            error.VersionNotInstalled => {
                try ctx.printer.append("Version {s} is not installed.\n\n", .{target_version}, .{});
            },
            else => {
                try ctx.printer.append("Installing failed\n\n", .{}, .{});
            },
        }
    };
    return;
}

fn artifactPrune(ctx: *Context, artifact: *Artifact) !void {
    _ = ctx;
    try artifact.prune();
    return;
}

fn artifactList(ctx: *Context, artifact: *Artifact) !void {
    _ = ctx;
    try artifact.list();
    return;
}

pub fn _artifactController(
    ctx: *Context,
    artifact_type: Structs.Extras.ArtifactType,
) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var artifact = try Artifact.init(
        ctx,
        artifact_type,
    );
    defer artifact.deinit();

    const arg = ctx.args[2];

    if (std.mem.eql(u8, arg, "install"))
        try artifactInstall(ctx, &artifact);

    if (std.mem.eql(u8, arg, "uninstall"))
        try artifactUninstall(ctx, &artifact);

    if (std.mem.eql(u8, arg, "switch"))
        try artifactSwitch(ctx, &artifact);

    if (std.mem.eql(u8, arg, "prune"))
        try artifactPrune(ctx, &artifact);

    if (std.mem.eql(u8, arg, "list") or
        std.mem.eql(u8, arg, "ls"))
        try artifactList(ctx, &artifact);
}
