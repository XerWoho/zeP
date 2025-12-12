const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;

const Json = @import("core").Json.Json;
const ZigInit = @import("core").ZigInit;

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

        var zig_version: []const u8 = "0.14.0";
        const child = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch |err| {
            switch (err) {
                else => {
                    try printer.append("Zig is not installed!\nExiting!\n\n", .{}, .{ .color = 31 });
                    try printer.append("\nSUGGESTION:\n", .{}, .{ .color = 34 });
                    try printer.append(" - Install zig\n $ zep zig install <version>\n\n", .{}, .{});
                    std.process.exit(0);
                },
            }
            return;
        };

        zig_version = child.stdout[0 .. child.stdout.len - 1];
        try printer.append("--- INITING ZEP MODE ---\n\n", .{}, .{ .color = 34 });
        const stdin = std.io.getStdIn().reader();

        const name = try Prompt.input(
            allocator,
            printer,
            stdin,
            "> *Name: ",
            .{
                .required = true,
            },
        );
        const description = try Prompt.input(
            allocator,
            printer,
            stdin,
            "> Description: ",
            .{},
        );
        const license = try Prompt.input(
            allocator,
            printer,
            stdin,
            "> License: ",
            .{},
        );

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

        try self.printer.append("Finished initing!\n", .{}, .{ .color = 32 });
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

        const gitignore = ".gitignore";
        const gitignore_main =
            \\.zig-cache
            \\
            \\zep-out
            \\
            \\.zep
            \\!.zep/injector.zig
        ;

        if (!Fs.existsFile(gitignore)) {
            const f = try Fs.openOrCreateFile(gitignore);
            _ = try f.write(gitignore_main);
        }
    }
};
