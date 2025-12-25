const std = @import("std");

const CustomPackage = @import("../../lib/packages/custom.zig").CustomPackage;
const Lister = @import("../../lib/packages/list.zig").Lister;
const Package = @import("core").Package;

const Context = @import("context").Context;

fn packageAdd(
    ctx: *Context,
) !void {
    try ctx.logger.info("running package: add", @src());
    var custom = CustomPackage.init(ctx);
    try custom.requestPackage();
    try ctx.logger.info("running package: add finished", @src());
    return;
}

fn packageRemove(
    ctx: *Context,
) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    try ctx.logger.info("running package: remove", @src());
    const package = ctx.args[3];
    var custom = CustomPackage.init(ctx);
    try custom.removePackage(package);
    try ctx.logger.info("running package: remove finished", @src());
    return;
}

fn packageList(ctx: *Context) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    try ctx.logger.info("running package: list", @src());
    const package = ctx.args[3];
    var split = std.mem.splitScalar(u8, package, '@');
    const package_name = split.first();
    var lister = Lister.init(ctx, package_name);
    lister.list() catch |err| {
        try ctx.logger.errf("running package: list failed, name={s} err={}", .{ package_name, err }, @src());
        try ctx.printer.append("\nListing {s} has failed...\n\n", .{package_name}, .{ .color = .red });
    };
    try ctx.logger.info("running package: list finished", @src());
}

fn packageInfo(ctx: *Context) !void {
    if (ctx.args.len < 4) return error.MissingArguments;

    const package_id = ctx.args[3];
    var split = std.mem.splitScalar(u8, package_id, '@');
    const package_name = split.first();
    const package_version = split.next();
    var package = try Package.init(
        ctx.allocator,
        &ctx.printer,
        &ctx.fetcher,
        package_name,
        package_version,
    );
    defer package.deinit();

    std.debug.print("Package Name: {s}\n", .{package_name});
    std.debug.print("Version: {s}\n", .{package.package.version});
    std.debug.print("Sha256Sum: {s}\n", .{package.package.sha256sum});
    std.debug.print("Url: {s}\n", .{package.package.url});
    std.debug.print("Root File: {s}\n", .{package.package.root_file});
    std.debug.print("Zig Version: {s}\n", .{package.package.zig_version});
    std.debug.print("\n", .{});
}

pub fn _packageController(ctx: *Context) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "add"))
        try packageAdd(ctx);

    if (std.mem.eql(u8, arg, "remove"))
        try packageRemove(ctx);

    if (std.mem.eql(u8, arg, "info"))
        try packageInfo(ctx);

    if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls"))
        try packageList(ctx);
}
