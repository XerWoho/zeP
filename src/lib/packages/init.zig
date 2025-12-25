const std = @import("std");

pub const Init = @This();

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;
const ZigInit = @import("core").ZigInit;

const Context = @import("context");

ctx: *Context,
zig_version: []const u8 = "0.14.0",
name: []const u8 = "",
description: []const u8 = "",
license: []const u8 = "",

pub fn init(
    ctx: *Context,
    default: bool,
) !Init {
    if (default) {
        return Init{
            .ctx = ctx,
        };
    }

    var zig_version: []const u8 = "0.14.0";
    const child = std.process.Child.run(.{
        .allocator = ctx.allocator,
        .argv = &[_][]const u8{ "zig", "version" },
    }) catch |err| {
        switch (err) {
            else => {
                try ctx.printer.append("Zig is not installed!\nExiting!\n\n", .{}, .{ .color = .red });
                try ctx.printer.append("\nSUGGESTION:\n", .{}, .{ .color = .blue });
                try ctx.printer.append(" - Install zig\n $ zep zig install <version>\n\n", .{}, .{});
            },
        }
        return error.ZigNotInstalled;
    };

    zig_version = child.stdout[0 .. child.stdout.len - 1];
    try ctx.printer.append("--- INITING ZEP MODE ---\n\n", .{}, .{
        .color = .blue,
        .weight = .bold,
    });
    var stdin_buf: [Constants.Default.kb * 4]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    const name = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        stdin,
        "> *Name: ",
        .{
            .required = true,
        },
    );
    const description = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        stdin,
        "> Description: ",
        .{},
    );
    const license = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        stdin,
        "> License: ",
        .{},
    );

    return Init{
        .ctx = ctx,

        .zig_version = zig_version,
        .license = license,
        .name = name,
        .description = description,
    };
}

pub fn commitInit(self: *Init) !void {
    try self.ctx.printer.append("Initing Zep project...\n", .{}, .{});

    try self.createFolders();
    try self.createFiles();

    // auto init zig
    try ZigInit.createZigProject(
        &self.ctx.printer,
        self.ctx.allocator,
        self.name,
        self.zig_version,
    );

    try self.ctx.printer.append("Finished initing!\n\n", .{}, .{ .color = .green });
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
        try self.ctx.json.writePretty(Constants.Extras.package_files.manifest, pkg);
    }

    if (!Fs.existsFile(Constants.Extras.package_files.lock)) {
        try self.ctx.json.writePretty(Constants.Extras.package_files.lock, lock);
    }

    const gitignore = ".gitignore";
    const gitignore_main =
        \\.zig-cache
        \\
        \\zep-out
        \\
        \\.zep
        \\!.zep/injector.zig
        \\!.zep/.conf
    ;

    if (!Fs.existsFile(gitignore)) {
        const f = try Fs.openFile(gitignore);
        _ = try f.write(gitignore_main);
    }
}
