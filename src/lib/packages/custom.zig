const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Hash = @import("core").Hash;

const Context = @import("context").Context;

pub const CustomPackage = struct {
    ctx: *Context,

    pub fn init(ctx: *Context) CustomPackage {
        return CustomPackage{
            .ctx = ctx,
        };
    }

    fn getOrDefault(value: []const u8, def: []const u8) []const u8 {
        return if (value.len > 0) value else def;
    }

    fn promptVersionData(self: CustomPackage, stdin: anytype) !Structs.Packages.PackageVersions {
        const url = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> *Url ([http(s)][.zip]): ",
            .{ .required = true, .validate = &verifyUrl },
        );
        const root_file = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> *Root file: ",
            .{
                .required = true,
            },
        );

        const version = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> Version [0.1.0]: ",
            .{},
        );

        const zig_version = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> Zig Version [0.14.0]: ",
            .{},
        );

        const hash = Hash.hashData(self.ctx.allocator, url) catch |err| {
            switch (err) {
                else => {
                    try self.ctx.printer.append("\nINVALID URL!\nABORTING!\n", .{}, .{ .color = .red });
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
        var stdin_buf: [128]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;

        try self.ctx.printer.append("--- ADDING CUSTOM PACKAGE MODE ---\n\n", .{}, .{
            .color = .yellow,
            .weight = .bold,
        });

        const package_name = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> *Package Name: ",
            .{
                .required = true,
            },
        );
        defer self.ctx.allocator.free(package_name);

        var buf: [256]u8 = undefined;
        const custom_package_path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.json",
            .{
                self.ctx.paths.custom,
                package_name,
            },
        );

        if (Fs.existsFile(custom_package_path)) {
            try self.ctx.printer.append("-- PACKAGE EXISTS [ADD VERSION MODE] --\n\n", .{}, .{
                .color = .yellow,
                .weight = .bold,
            });

            const v = try self.promptVersionData(stdin);
            try self.addVersionToPackage(custom_package_path, v);

            try self.ctx.printer.append("\nSuccessfully added new version - {s}\n\n", .{v.version}, .{ .color = .green });
            return;
        }

        // New package mode
        const author = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            "> Author: ",
            .{},
        );
        defer self.ctx.allocator.free(author);

        const v = self.promptVersionData(stdin) catch |err| {
            switch (err) {
                error.InvalidUrl => return,
                else => return,
            }
            return;
        };

        var versions = try std.ArrayList(Structs.Packages.PackageVersions).initCapacity(self.ctx.allocator, 10);
        try versions.append(self.ctx.allocator, v);

        const pkg = Structs.Packages.PackageStruct{
            .name = package_name,
            .author = author,
            .docs = "",
            .versions = versions.items,
        };

        try self.addPackage(custom_package_path, pkg);
        try self.ctx.printer.append("\nSuccessfully added custom package - {s}\n\n", .{package_name}, .{ .color = .green });
    }

    fn addPackage(self: CustomPackage, custom_package_path: []const u8, package_json: Structs.Packages.PackageStruct) !void {
        if (Fs.existsFile(custom_package_path)) {
            try Fs.deleteFileIfExists(custom_package_path);
        }

        const package_file = try Fs.openOrCreateFile(custom_package_path);
        const stringify = try std.json.Stringify.valueAlloc(self.ctx.allocator, package_json, .{ .whitespace = .indent_2 });
        defer self.ctx.allocator.free(stringify);

        _ = try package_file.write(stringify);
    }

    fn addVersionToPackage(self: CustomPackage, custom_package_path: []const u8, version: Structs.Packages.PackageVersions) !void {
        const package_file = try Fs.openOrCreateFile(custom_package_path);
        defer package_file.close();
        const data = try package_file.readToEndAlloc(self.ctx.allocator, Constants.Default.mb * 5);
        var parsed: std.json.Parsed(Structs.Packages.PackageStruct) = try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.ctx.allocator, data, .{});
        defer parsed.deinit();

        var versions_array = try std.ArrayList(Structs.Packages.PackageVersions).initCapacity(self.ctx.allocator, 10);
        const versions = parsed.value.versions;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, version.version)) {
                try self.ctx.printer.append("\nSpecified version already in use!\nOverwriting...\n", .{}, .{ .color = .red });
                continue;
            }
            try versions_array.append(self.ctx.allocator, v);
        }
        try versions_array.append(self.ctx.allocator, version);
        parsed.value.versions = versions_array.items;
        const stringify = try std.json.Stringify.valueAlloc(self.ctx.allocator, parsed.value, .{ .whitespace = .indent_2 });
        defer self.ctx.allocator.free(stringify);

        try package_file.seekTo(0);
        try package_file.setEndPos(0);
        _ = try package_file.write(stringify);
    }

    pub fn removePackage(self: CustomPackage, package_name: []const u8) !void {
        try self.ctx.printer.append("Removing package...\n", .{}, .{});

        var buf: [256]u8 = undefined;
        const custom_package_path = try std.fmt.bufPrint(
            &buf,
            "{s}/{s}.json",
            .{ self.ctx.paths.custom, package_name },
        );

        if (Fs.existsFile(custom_package_path)) {
            try self.ctx.printer.append("Package found...\n", .{}, .{});
            try Fs.deleteFileIfExists(custom_package_path);
            try self.ctx.printer.append("Deleted.\n\n", .{}, .{});
        } else {
            try self.ctx.printer.append("Package not found...\n\n", .{}, .{});
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
