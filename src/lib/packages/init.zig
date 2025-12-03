const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const Json = @import("core").Json.Json;
const ZigInit = @import("core").ZigInit;

fn promptInput(stdin: anytype, prompt: []const u8, required: bool, printer: *Printer, allocator: std.mem.Allocator) ![]const u8 {
    try printer.append("{s}", .{prompt}, .{});
    var line: []const u8 = "";

    while (true) {
        var read_line = try stdin.readUntilDelimiterAlloc(allocator, '\n', Constants.Default.kb);
        if (required and read_line.len <= 1) {
            allocator.free(read_line);
            try printer.print();
            continue;
        }

        line = read_line[0 .. read_line.len - 1];
        break;
    }

    try printer.append("{s}\n", .{line}, .{});
    return line;
}

pub const Init = struct {
    allocator: std.mem.Allocator,
    json: Json,
    printer: *Printer,

    zig_version: []const u8 = "0.14.0",
    name: []const u8 = "",
    description: []const u8 = "",
    license: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, printer: *Printer, default: bool) !Init {
        const json = try Json.init(allocator);
        if (default) {
            return Init{
                .allocator = allocator,
                .json = json,
                .printer = printer,
            };
        }

        const child = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        });
        const zig_version = child.stdout[0 .. child.stdout.len - 1];

        try printer.append("--- INITTING ZEP MODE ---\n\n", .{}, .{ .color = 34 });
        const stdin = std.io.getStdIn().reader();

        const name = try promptInput(stdin, "> *Name: ", true, printer, allocator);
        const description = try promptInput(stdin, "> Description: ", false, printer, allocator);
        const license = try promptInput(stdin, "> License: ", false, printer, allocator);

        return Init{
            .allocator = allocator,
            .json = json,
            .zig_version = zig_version,
            .printer = printer,

            .license = license,
            .name = name,
            .description = description,
        };
    }

    pub fn commitInit(self: *Init) !void {
        try self.printer.append("Initing zep project...\n", .{}, .{});

        try self.createFolders();
        try self.createFiles();

        // auto init zig
        try ZigInit.createZigProject(
            self.printer,
            self.allocator,
            self.name,
            self.zig_version,
        );

        try self.printer.append("Finished initting!\n", .{}, .{ .color = 32 });
    }

    fn createFolders(_: *Init) !void {
        const cwd = std.fs.cwd();
        _ = cwd.makeDir(Constants.Extras.package_files.zep_folder) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn createFiles(self: *Init) !void {
        var pkg = Structs.ZepFiles.PackageJsonStruct{
            .build = Structs.ZepFiles.BuildPackageJsonStruct{},
        };
        pkg.zig_version = self.zig_version;

        const lock = Structs.ZepFiles.PackageLockStruct{ .root = pkg };

        if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
            try self.json.writePretty(Constants.Extras.package_files.manifest, pkg);
        }

        if (!Fs.existsFile(Constants.Extras.package_files.lock)) {
            try self.json.writePretty(Constants.Extras.package_files.lock, lock);
        }
    }
};
