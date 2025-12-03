const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;
const Hash = @import("core").Hash;

pub const CustomPackage = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *Printer) CustomPackage {
        return CustomPackage{ .allocator = allocator, .printer = printer };
    }

    fn getOrDefault(value: []const u8, def: []const u8) []const u8 {
        return if (value.len > 0) value else def;
    }

    fn promptVersionData(self: CustomPackage, stdin: anytype) !Structs.Packages.PackageVersions {
        const url = try self.promptInput(stdin, "Url (required [.zip]): ", true, verifyUrl);
        const root_file = try self.promptInput(stdin, "Root file (required): ", true, null);
        const version = try self.promptInput(stdin, "Version (optional) [def: 0.1.0]: ", false, null);
        const zig_version = try self.promptInput(stdin, "Zig Version (recommended) [def: 0.14.0]: ", false, null);

        const hash = try Hash.hashData(self.allocator, url);
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

        try self.printer.append("--- ADDING CUSTOM PACKAGE MODE ---\n\n", .{}, .{ .color = 33 });

        const package_name = try self.promptInput(stdin, "Package Name: ", true, null);
        defer self.allocator.free(package_name);

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const custom_package_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{
            paths.custom,
            package_name,
        });
        defer self.allocator.free(custom_package_path);

        if (Fs.existsFile(custom_package_path)) {
            try self.printer.append("-- PACKAGE EXISTS [ADD VERSION MODE] --\n\n", .{}, .{ .color = 33 });

            const v = try self.promptVersionData(stdin);
            try self.addVersionToPackage(custom_package_path, v);

            try self.printer.append("\nSuccessfully added new version - {s}\n\n", .{v.version}, .{ .color = 32 });
            return;
        }

        // New package mode
        const author = try self.promptInput(stdin, "Author (optional): ", false, null);
        defer self.allocator.free(author);

        const v = try self.promptVersionData(stdin);

        var versions = std.ArrayList(Structs.Packages.PackageVersions).init(self.allocator);
        try versions.append(v);

        const pkg = Structs.Packages.PackageStruct{
            .name = package_name,
            .author = author,
            .docs = "",
            .versions = versions.items,
        };

        try self.addPackage(custom_package_path, pkg);
        try self.printer.append("\nSuccessfully added custom package - {s}\n\n", .{package_name}, .{ .color = 32 });
    }

    fn promptInput(self: CustomPackage, stdin: anytype, prompt: []const u8, required: bool, validate: ?fn (a: []const u8) bool) ![]const u8 {
        try self.printer.append("{s}", .{prompt}, .{});
        var line: []const u8 = "";

        if (required or validate != null) {
            while (true) {
                var read_line = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', Constants.Default.kb);
                if (required and read_line.len <= 1) {
                    self.allocator.free(read_line);
                    try self.printer.print();
                    continue;
                }
                if (validate) |v| {
                    if (!v(if (builtin.os.tag == .windows) read_line[0 .. read_line.len - 1] else read_line)) {
                        self.allocator.free(read_line);
                        try self.printer.print();
                        continue;
                    }
                }

                line = if (builtin.os.tag == .windows) read_line[0 .. read_line.len - 1] else read_line;
                break;
            }
        } else {
            var read_line = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', Constants.Default.kb);
            line = if (builtin.os.tag == .windows) read_line[0 .. read_line.len - 1] else read_line;
        }

        try self.printer.append("{s}\n", .{line}, .{});
        return line;
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
                try self.printer.append("\nSpecified version already in use!\nOverwriting...\n", .{}, .{ .color = 31 });
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

        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();
        const custom_package_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ paths.custom, package_name });
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
