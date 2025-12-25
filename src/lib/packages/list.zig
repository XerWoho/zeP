const std = @import("std");

pub const Lister = @This();
const Context = @import("context");

ctx: *Context,
package_name: []const u8,

pub fn init(
    ctx: *Context,
    package_name: []const u8,
) Lister {
    return Lister{
        .ctx = ctx,
        .package_name = package_name,
    };
}

pub fn list(self: *Lister) !void {
    const parsed_package = self.ctx.fetcher.fetchPackage(self.package_name) catch |err| {
        switch (err) {
            error.PackageNotFound => {
                try self.ctx.printer.append("Package not found...\n\n", .{}, .{ .color = .red });
                return;
            },
            else => {
                try self.ctx.printer.append("Parsing package failed...\n\n", .{}, .{ .color = .red });
                return;
            },
        }
    };
    defer parsed_package.deinit();

    try self.ctx.printer.append("Package Found! - {s}\n\n", .{self.package_name}, .{ .color = .green });

    const versions = parsed_package.value.versions;
    try self.ctx.printer.append("Available versions:\n", .{}, .{});
    if (versions.len == 0) {
        try self.ctx.printer.append("  NO VERSIONS FOUND!\n\n", .{}, .{ .color = .red });
        return;
    } else {
        for (versions) |v| {
            try self.ctx.printer.append("  > version: {s} (zig: {s})\n", .{ v.version, v.zig_version }, .{});
        }
    }
    try self.ctx.printer.append("\n", .{}, .{});

    return;
}
