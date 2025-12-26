const std = @import("std");

const Context = @import("context");

pub fn list(
    ctx: *Context,
    package_name: []const u8,
) !void {
    const parsed_package = try ctx.fetcher.fetchPackage(package_name);
    defer parsed_package.deinit();

    try ctx.printer.append("Package Found! - {s}\n\n", .{package_name}, .{ .color = .green });

    const versions = parsed_package.value.versions;
    try ctx.printer.append("Available versions:\n", .{}, .{});
    if (versions.len == 0) {
        try ctx.printer.append("  NO VERSIONS FOUND!\n\n", .{}, .{ .color = .red });
        return;
    } else {
        for (versions) |v| {
            try ctx.printer.append("  > version: {s} (zig: {s})\n", .{ v.version, v.zig_version }, .{});
        }
    }
    try ctx.printer.append("\n", .{}, .{});
    return;
}
