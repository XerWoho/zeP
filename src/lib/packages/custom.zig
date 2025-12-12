const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Hash = @import("core").Hash;

pub const CustomPackage = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    paths: *Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        paths: *Constants.Paths.Paths,
    ) CustomPackage {
        return CustomPackage{ .allocator = allocator, .printer = printer, .paths = paths };
    }

    fn getOrDefault(value: []const u8, def: []const u8) []const u8 {
        return if (value.len > 0) value else def;
    }

    fn promptVersionData(self: CustomPackage, stdin: anytype) !Structs.Packages.PackageVersions {
        const url = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> *Url ([http(s)][.zip]): ",
            .{ .required = true, .validate = &verifyUrl },
        );
        const root_file = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> *Root file: ",
            .{
                .required = true,
            },
        );

        const version = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> Version [0.1.0]: ",
            .{},
        );

        const zig_version = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> Zig Version [0.14.0]: ",
            .{},
        );

        const hash = Hash.hashData(self.allocator, url) catch |err| {
            switch (err) {
                else => {
                    try self.printer.append("\nINVALID URL!\nABORTING!\n", .{}, .{ .color = .red });
                },
            }
            return error.InvalidUrl;
        };
        return .{
            .version = getOrDefault(version, "0.1.0"),
            .url = url,
            .sha256sum = hash,
            .root_file = root_file,
            .zig_version = getOrDefault(zig_version, "0.14.0"),
        };
    }

    pub fn requestPackage(self: CustomPackage) !void {
        const stdin = std.io.getStdIn().reader();

        try self.printer.append("--- ADDING CUSTOM PACKAGE MODE ---\n\n", .{}, .{
            .color = .yellow,
            .weight = .bold,
        });

        const package_name = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> *Package Name: ",
            .{
                .required = true,
            },
        );
        defer self.allocator.free(package_name);

        const custom_package_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{
            self.paths.custom,
            package_name,
        });
        defer self.allocator.free(custom_package_path);

        if (Fs.existsFile(custom_package_path)) {
            try self.printer.append("-- PACKAGE EXISTS [ADD VERSION MODE] --\n\n", .{}, .{
                .color = .yellow,
                .weight = .bold,
            });

            const v = try self.promptVersionData(stdin);
            try self.addVersionToPackage(custom_package_path, v);

            try self.printer.append("\nSuccessfully added new version - {s}\n\n", .{v.version}, .{ .color = .green });
            return;
        }

        // New package mode
        const author = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> Author: ",
            .{},
        );
        defer self.allocator.free(author);

        const v = self.promptVersionData(stdin) catch |err| {
            switch (err) {
                error.InvalidUrl => return,
                else => return,
            }
            return;
        };

        var versions = std.ArrayList(Structs.Packages.PackageVersions).init(self.allocator);
        try versions.append(v);

        const pkg = Structs.Packages.PackageStruct{
            .name = package_name,
            .author = author,
            .docs = "",
            .versions = versions.items,
        };

        try self.addPackage(custom_package_path, pkg);
        try self.printer.append("\nSuccessfully added custom package - {s}\n\n", .{package_name}, .{ .color = .green });
    }

    fn addPackage(self: CustomPackage, custom_package_path: []const u8, package_json: Structs.Packages.PackageStruct) !void {
        if (Fs.existsFile(custom_package_path)) {
            try Fs.deleteFileIfExists(custom_package_path);
        }

        const package_file = try Fs.openOrCreateFile(custom_package_path);
        const stringify = try std.json.stringifyAlloc(self.allocator, package_json, .{ .whitespace = .indent_2 });
        defer self.allocator.free(stringify);

        _ = try package_file.write(stringify);
    }

    fn addVersionToPackage(self: CustomPackage, custom_package_path: []const u8, version: Structs.Packages.PackageVersions) !void {
        const package_file = try Fs.openOrCreateFile(custom_package_path);
        defer package_file.close();
        const data = try package_file.readToEndAlloc(self.allocator, Constants.Default.mb * 5);
        var parsed: std.json.Parsed(Structs.Packages.PackageStruct) = try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.allocator, data, .{});
        defer parsed.deinit();

        var versions_array = std.ArrayList(Structs.Packages.PackageVersions).init(self.allocator);
        const versions = parsed.value.versions;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, version.version)) {
                try self.printer.append("\nSpecified version already in use!\nOverwriting...\n", .{}, .{ .color = .red });
                continue;
            }
            try versions_array.append(v);
        }
        try versions_array.append(version);
        parsed.value.versions = versions_array.items;
        const stringify = try std.json.stringifyAlloc(self.allocator, parsed.value, .{ .whitespace = .indent_2 });
        defer self.allocator.free(stringify);

        try package_file.seekTo(0);
        try package_file.setEndPos(0);
        _ = try package_file.write(stringify);
    }

    pub fn removePackage(self: CustomPackage, package_name: []const u8) !void {
        try self.printer.append("Removing package...\n", .{}, .{});

        const custom_package_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.paths.custom, package_name });
        defer self.allocator.free(custom_package_path);

        if (Fs.existsFile(custom_package_path)) {
            try self.printer.append("Package found...\n", .{}, .{});
            try Fs.deleteFileIfExists(custom_package_path);
            try self.printer.append("Deleted.\n\n", .{}, .{});
        } else {
            try self.printer.append("Package not found...\n\n", .{}, .{});
        }
    }
};

const ALLOWED_EXTENSIONS = &[1][]const u8{".zip"};
fn verifyUrl(url: []const u8) bool {
    if (!std.mem.startsWith(u8, url, "http://") and
        !std.mem.startsWith(u8, url, "https://")) return false;

    blk: {
        for (ALLOWED_EXTENSIONS) |extension| {
            if (std.mem.endsWith(u8, url, extension)) break :blk;
            continue;
        }
        return false;
    }

    return true;
}
