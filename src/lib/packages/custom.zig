const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Utils = @import("utils");

const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsHash = Utils.UtilsHash;

pub const CustomPackage = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) CustomPackage {
        return CustomPackage{ .allocator = allocator, .printer = printer };
    }

    fn getOrDefault(value: []const u8, def: []const u8) []const u8 {
        return if (value.len > 0) value else def;
    }

    fn promptVersionData(self: CustomPackage, stdin: anytype) !Structs.PackageVersions {
        const url = try self.promptInput(stdin, "Url (required [.zip]): ", true);
        const rootFile = try self.promptInput(stdin, "Root file (required): ", true);
        const version = try self.promptInput(stdin, "Version (optional) [def: 0.1.0]: ", false);
        const zigVer = try self.promptInput(stdin, "Zig Version (recommended) [def: 0.14.0]: ", false);

        // defers
        // defer self.allocator.free(url);
        // defer self.allocator.free(rootFile);
        // defer self.allocator.free(version);
        // defer self.allocator.free(zigVer);

        const hash = try UtilsHash.hashData(self.allocator, url);

        return .{
            .version = getOrDefault(version, "0.1.0"),
            .url = url,
            .sha256sum = hash,
            .rootFile = rootFile,
            .zigVersion = getOrDefault(zigVer, "0.14.0"),
        };
    }

    pub fn requestPackage(self: CustomPackage) !void {
        const stdin = std.io.getStdIn().reader();
        try self.printer.append("--- ADDING CUSTOM PACKAGE MODE ---\n\n", .{}, .{ .color = 33 });

        const packageName = try self.promptInput(stdin, "Package Name: ", true);
        defer self.allocator.free(packageName);

        const pkgPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{
            Constants.ROOT_ZEP_CUSTOM_PACKAGES,
            packageName,
        });
        defer self.allocator.free(pkgPath);

        if (UtilsFs.checkFileExists(pkgPath)) {
            try self.printer.append("-- PACKAGE EXISTS [ADD VERSION MODE] --\n\n", .{}, .{ .color = 33 });

            const v = try self.promptVersionData(stdin);
            try self.addVersionToPackage(pkgPath, v);

            try self.printer.append("\nSuccessfully added new version - {s}\n\n", .{v.version}, .{ .color = 32 });
            return;
        }

        // New package mode
        const author = try self.promptInput(stdin, "Author (optional): ", false);
        defer self.allocator.free(author);

        const v = try self.promptVersionData(stdin);

        var versions = std.ArrayList(Structs.PackageVersions).init(self.allocator);
        try versions.append(v);

        const pkg = Structs.PackageStruct{
            .name = packageName,
            .author = author,
            .docs = "",
            .versions = versions.items,
        };

        try self.addPackage(pkgPath, pkg);
        try self.printer.append("\nSuccessfully added custom package - {s}\n\n", .{packageName}, .{ .color = 32 });
    }

    fn promptInput(self: CustomPackage, stdin: std.fs.File.Reader, prompt: []const u8, required: bool) ![]const u8 {
        try self.printer.append("{s}", .{prompt}, .{});
        var line: []const u8 = "";

        while (required) {
            var readLine = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 1024);
            if (readLine.len <= 1) {
                self.allocator.free(readLine);
                try self.printer.print();
                continue;
            }
            line = readLine[0 .. readLine.len - 1];
            break;
        }

        if (!required) {
            var readLine = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 1024);
            line = readLine[0 .. readLine.len - 1];
        }

        try self.printer.append("{s}\n", .{line}, .{});
        return line;
    }

    fn addPackage(self: CustomPackage, pkgPath: []const u8, packageJson: Structs.PackageStruct) !void {
        if (UtilsFs.checkFileExists(pkgPath)) {
            try std.fs.cwd().deleteFile(pkgPath);
        }

        const pkgFile = try UtilsFs.openCFile(pkgPath);
        const stringify = try std.json.stringifyAlloc(self.allocator, packageJson, .{ .whitespace = .indent_2 });
        defer self.allocator.free(stringify);

        _ = try pkgFile.write(stringify);
    }

    fn addVersionToPackage(self: CustomPackage, pkgPath: []const u8, version: Structs.PackageVersions) !void {
        const pkgFile = try UtilsFs.openCFile(pkgPath);
        defer pkgFile.close();
        const data = try pkgFile.readToEndAlloc(self.allocator, 1024 * 1024 * 5);
        var parsed = try std.json.parseFromSlice(Structs.PackageStruct, self.allocator, data, .{});
        defer parsed.deinit();

        var versionsArray = std.ArrayList(Structs.PackageVersions).init(self.allocator);
        const versions = parsed.value.versions;
        for (versions) |v| {
            if (std.mem.eql(u8, v.version, version.version)) {
                try self.printer.append("\nSpecified version already in use!\nOverwriting...\n", .{}, .{ .color = 31 });
                continue;
            }
            try versionsArray.append(v);
        }
        try versionsArray.append(version);
        parsed.value.versions = versionsArray.items;
        const stringify = try std.json.stringifyAlloc(self.allocator, parsed.value, .{ .whitespace = .indent_2 });
        defer self.allocator.free(stringify);

        try pkgFile.seekTo(0);
        try pkgFile.setEndPos(0);
        _ = try pkgFile.write(stringify);
    }

    pub fn removePackage(self: CustomPackage, packageName: []const u8) !void {
        try self.printer.append("Removing package...\n", .{}, .{});

        const pkgPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ Constants.ROOT_ZEP_CUSTOM_PACKAGES, packageName });
        defer self.allocator.free(pkgPath);

        if (UtilsFs.checkFileExists(pkgPath)) {
            try self.printer.append("Package found...\n", .{}, .{});
            try std.fs.cwd().deleteFile(pkgPath);
            try self.printer.append("Deleted.\n\n", .{}, .{});
        } else {
            try self.printer.append("Package not found...\n\n", .{}, .{});
        }
    }
};
