const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

pub const PackageFiles = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !PackageFiles {
        const runner = PackageFiles{ .allocator = allocator, .printer = printer };
        if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
            try printer.append("\nNo zep.json file!\n", .{}, .{ .color = 31 });
            std.process.exit(0);
            return runner;
        }

        return runner;
    }

    fn promptInput(self: *PackageFiles, stdin: anytype, prompt: []const u8, initial_value: []const u8) ![]const u8 {
        try self.printer.append("{s}", .{prompt}, .{});
        var line: []const u8 = "";
        const stdout = std.io.getStdOut().writer();

        _ = try stdout.write(initial_value);
        _ = try stdout.write(" => ");

        var read_line = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', Constants.Default.kb);
        line = if (builtin.os.tag == .windows) read_line[0 .. read_line.len - 1] else read_line;

        if (line.len == 0) {
            try self.printer.append("{s}\n", .{initial_value}, .{});
            return try self.allocator.dupe(u8, initial_value);
        }
        try self.printer.append("{s}\n", .{line}, .{});
        return line;
    }

    pub fn json(self: *PackageFiles) !void {
        var zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        const stdin = std.io.getStdIn().reader();
        try self.printer.append("--- MODIFYING JSON MODE ---\n", .{}, .{ .color = 33 });
        try self.printer.append("(leave empty to keep same)\n\n", .{}, .{ .color = 33 });
        const author = try self.promptInput(stdin, "Author: ", zep_json.value.author);
        defer self.allocator.free(author);
        const description = try self.promptInput(stdin, "Description: ", zep_json.value.description);
        defer self.allocator.free(description);
        const name = try self.promptInput(stdin, "Name: ", zep_json.value.name);
        defer self.allocator.free(name);
        const license = try self.promptInput(stdin, "License: ", zep_json.value.license);
        defer self.allocator.free(license);
        const repo = try self.promptInput(stdin, "Repo: ", zep_json.value.repo);
        defer self.allocator.free(repo);
        const version = try self.promptInput(stdin, "Version: ", zep_json.value.version);
        defer self.allocator.free(version);
        const zig_version = try self.promptInput(stdin, "Zig Version: ", zep_json.value.zig_version);
        defer self.allocator.free(zig_version);

        zep_json.value.name = name;
        zep_json.value.license = license;
        zep_json.value.author = author;
        zep_json.value.description = description;
        zep_json.value.repo = repo;
        zep_json.value.version = version;
        zep_json.value.zig_version = zig_version;

        try Manifest.writeManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest, zep_json.value);

        var zep_lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer zep_lock.deinit();
        zep_lock.value.root = zep_json.value;

        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock, zep_lock.value);
        try self.printer.append("\nSuccessfully modified zep.json!\n\n", .{}, .{ .color = 32 });
        return;
    }

    pub fn lock(self: *PackageFiles) !void {
        var zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        var zep_lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer zep_lock.deinit();
        zep_lock.value.root = zep_json.value;
        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock, zep_lock.value);

        try self.printer.append("Successfully moved zep.json into zep.lock!\n\n", .{}, .{ .color = 32 });
        return;
    }
};
