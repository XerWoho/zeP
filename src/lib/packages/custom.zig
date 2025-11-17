const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

pub const CustomPackage = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) CustomPackage {
        return CustomPackage{ .allocator = allocator, .printer = printer };
    }

    pub fn requestPackage(self: CustomPackage) !void {
        const stdin = std.io.getStdIn().reader();
        try self.printer.append("--- ADDING PACKAGE MODE ---\n\n");

        const packageName = try self.promptInput(stdin, "Package Name: ");
        const author = try self.promptInput(stdin, "Author (optional): ");
        const git = try self.promptInput(stdin, "Git Url (required): ");
        const root_file = try self.promptInput(stdin, "Root file (required): ");
        const description = try self.promptInput(stdin, "Description (optional): ");

        const pkg = Structs.PackageStruct{
            .author = author,
            .git = git,
            .root_file = root_file,
            .description = description,
            .tags = &[_][]const u8{},
            .homepage = "",
            .license = "",
            .updated_at = "",
        };

        const pkgPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ Constants.ROOT_ZEP_CUSTOM_PACKAGES, packageName });
        defer self.allocator.free(pkgPath);

        try self.addPackage(pkgPath, pkg);
    }

    fn promptInput(self: CustomPackage, stdin: std.fs.File.Reader, prompt: []const u8) ![]const u8 {
        try self.printer.append(prompt);
        var line = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 1024);
        defer self.allocator.free(line);

        // Remove trailing newline if present
        if (line.len > 0 and line[line.len - 1] == '\n') {
            line = line[0 .. line.len - 1];
        }

        try self.printer.append(line);
        try self.printer.append("\n");
        return line;
    }

    fn addPackage(self: CustomPackage, pkgPath: []const u8, packageJson: Structs.PackageStruct) !void {
        if (try UtilsFs.checkFileExists(pkgPath)) {
            try std.fs.cwd().deleteFile(pkgPath);
        }

        const pkgFile = try UtilsFs.openCFile(pkgPath);
        const stringify = try std.json.stringifyAlloc(self.allocator, packageJson, .{ .whitespace = .indent_2 });
        defer self.allocator.free(stringify);

        _ = try pkgFile.write(stringify);
    }

    pub fn removePackage(self: CustomPackage, packageName: []const u8) !void {
        try self.printer.append("Removing package...\n");

        const pkgPath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ Constants.ROOT_ZEP_CUSTOM_PACKAGES, packageName });
        defer self.allocator.free(pkgPath);

        if (try UtilsFs.checkFileExists(pkgPath)) {
            try self.printer.append("Package found...\n");
            try std.fs.cwd().deleteFile(pkgPath);
            try self.printer.append("Deleted.\n\n");
        } else {
            try self.printer.append("Package not found...\n\n");
        }
    }
};
