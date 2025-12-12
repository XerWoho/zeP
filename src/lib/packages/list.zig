const std = @import("std");

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Json = @import("core").Json.Json;
const Package = @import("core").Package.Package;
const Printer = @import("cli").Printer;

const Init = @import("init.zig");
const Uninstaller = @import("uninstall.zig");

pub const Lister = struct {
    allocator: std.mem.Allocator,
    json: *Json,
    printer: *Printer,
    package_name: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        json: *Json,
        package_name: []const u8,
    ) Lister {
        return Lister{
            .json = json,
            .allocator = allocator,
            .printer = printer,
            .package_name = package_name,
        };
    }

    pub fn list(self: *Lister) !void {
        const parsed_package = self.json.parsePackage(self.package_name) catch |err| {
            switch (err) {
                error.PackageNotFound => {
                    try self.printer.append("Package not found...\n\n", .{}, .{ .color = .red });
                    return;
                },
                else => {
                    try self.printer.append("Parsing package failed...\n\n", .{}, .{ .color = .red });
                    return;
                },
            }
        };
        defer parsed_package.deinit();

        try self.printer.append("Package Found! - {s}.json\n\n", .{self.package_name}, .{ .color = .green });

        const versions = parsed_package.value.versions;
        try self.printer.append("Available versions:\n", .{}, .{});
        if (versions.len == 0) {
            try self.printer.append("  NO VERSIONS FOUND!\n\n", .{}, .{ .color = .red });
        } else {
            for (versions) |v| {
                try self.printer.append("  > version: {s} (zig: {s})\n", .{ v.version, v.zig_version }, .{});
            }
        }

        return;
    }
};
