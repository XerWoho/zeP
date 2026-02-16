const std = @import("std");

const Context = @import("context");
const Args = @import("args");

const Structs = @import("structs");
const Errors = @import("errors");

const Resolver = @import("resolver");

pub fn list(
    ctx: *Context,
    name: []const u8,
) Errors.Installable!void {
    ctx.logger.info("Listing Package", @src());

    const install_args = Args.parseInstall(ctx.options);
    var namespace: Structs.Extras.Namespaces = .zep;
    if (install_args.zep) namespace = Structs.Extras.Namespaces.zep;
    if (install_args.github) namespace = Structs.Extras.Namespaces.github;
    if (install_args.gitlab) namespace = Structs.Extras.Namespaces.gitlab;
    if (install_args.codeberg) namespace = Structs.Extras.Namespaces.codeberg;
    if (install_args.local) namespace = Structs.Extras.Namespaces.local;

    var resolver = Resolver.init(ctx);
    var package = try resolver.fetchPackage(
        name,
        namespace,
    );
    defer package.deinit(ctx.allocator);
    ctx.printer.append("Available versions for {s}:\n", .{name}, .{});

    const versions = package.versions;
    if (versions.len == 0) {
        ctx.printer.append("  NO VERSIONS FOUND!\n\n", .{}, .{ .color = .red });
        return;
    } else {
        for (versions) |v| {
            ctx.printer.append(" > version: {s} (zig: {s})\n", .{ v.version, v.zig_version }, .{});
        }
    }
    ctx.printer.append("\n", .{}, .{});
}
