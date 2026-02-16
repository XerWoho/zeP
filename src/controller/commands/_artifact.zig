const std = @import("std");
const Structs = @import("structs");
const Constants = @import("constants");
const Locales = @import("locales");

const Artifact = @import("../../lib/artifact/artifact.zig");
const Context = @import("context");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn artifactInstall(ctx: *Context, artifact: *Artifact) void {
    const target_version = if (ctx.cmds.len < 4) "latest" else ctx.cmds[3];
    const target = if (ctx.cmds.len < 5) Constants.Default.resolveDefaultTarget() else ctx.cmds[4];

    artifact.install(target_version, target) catch |err| CErrors.handleArtifactError(
        ctx,
        err,
        "install",
        target_version,
    );
}

fn artifactUninstall(ctx: *Context, artifact: *Artifact) void {
    const target_version = ctx.cmds[3];
    const target = if (ctx.cmds.len < 5) Constants.Default.resolveDefaultTarget() else ctx.cmds[4];

    artifact.uninstall(target_version, target) catch |err| CErrors.handleArtifactError(
        ctx,
        err,
        "uninstall",
        target_version,
    );
}

fn artifactSwitch(ctx: *Context, artifact: *Artifact) void {
    const target_version = ctx.cmds[3];
    const target = if (ctx.cmds.len < 5) Constants.Default.resolveDefaultTarget() else ctx.cmds[4];

    artifact.switchVersion(target_version, target) catch |err| CErrors.handleArtifactError(
        ctx,
        err,
        "switch",
        target_version,
    );
}

fn artifactList(ctx: *Context, artifact: *Artifact) void {
    artifact.list() catch |err| CErrors.handleArtifactError(
        ctx,
        err,
        "List",
        "/",
    );
}

fn artifactUpgrade(ctx: *Context, artifact: *Artifact) void {
    const target = if (ctx.cmds.len < 4) Constants.Default.resolveDefaultTarget() else ctx.cmds[3];

    artifact.install("latest", target) catch |err| CErrors.handleArtifactError(
        ctx,
        err,
        "upgrade",
        "latest",
    );
}

fn artifactCache(ctx: *Context, artifact: *Artifact) void {
    const cache_cmd = ctx.cmds[3];
    if (std.mem.eql(u8, cache_cmd, "list")) {
        artifact.listCache() catch |err| CErrors.handleCacheError(
            ctx,
            err,
            "list",
        );
    } else if (std.mem.eql(u8, cache_cmd, "size")) {
        artifact.sizeCache() catch |err| CErrors.handleCacheError(
            ctx,
            err,
            "size",
        );
    } else if (std.mem.eql(u8, cache_cmd, "clean")) {
        const target_version = if (ctx.cmds.len < 5) null else ctx.cmds[4];
        artifact.cleanCache(target_version) catch |err| CErrors.handleCacheError(
            ctx,
            err,
            "clean",
        );
    }
}

pub fn _artifactController(
    ctx: *Context,
    artifact_type: Structs.Extras.ArtifactType,
) Errors.Controller.Main!void {
    if (ctx.cmds.len < 3) {
        switch (artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        }
    }

    var artifact = Artifact.init(
        ctx,
        artifact_type,
    );
    defer artifact.deinit();

    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "install")) {
        if (ctx.cmds.len < 4) switch (artifact.artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        };

        artifactInstall(ctx, &artifact);
    } else if (std.mem.eql(u8, arg, "uninstall")) {
        if (ctx.cmds.len < 4) switch (artifact.artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        };

        artifactUninstall(ctx, &artifact);
    } else if (std.mem.eql(u8, arg, "upgrade")) {
        artifactUpgrade(ctx, &artifact);
    } else if (std.mem.eql(u8, arg, "switch")) {
        if (ctx.cmds.len < 4) switch (artifact.artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        };

        artifactSwitch(ctx, &artifact);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        artifactList(ctx, &artifact);
    } else if (std.mem.eql(u8, arg, "cache")) {
        if (ctx.cmds.len < 4) switch (artifact.artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        };
        artifactCache(ctx, &artifact);
    } else {
        switch (artifact_type) {
            .zep => return Errors.Controller.MissingSubcommand.Zep,
            .zig => return Errors.Controller.MissingSubcommand.Zig,
        }
    }
}
