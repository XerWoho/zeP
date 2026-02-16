const std = @import("std");

pub const Init = @This();

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;
const ZigInit = @import("core").ZigInit;
const Json = @import("core").Json;

const Context = @import("context");

ctx: *Context,
zig_version: []const u8 = Constants.Default.zig_version,
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
    ctx.logger.info("Initializing", @src());

    var zig_version: []const u8 = Constants.Default.zig_version;
    const child = std.process.Child.run(.{
        .allocator = ctx.allocator,
        .argv = &[_][]const u8{ "zig", "version" },
    }) catch |err| {
        switch (err) {
            else => {
                ctx.printer.append("Zig is not installed!\nExiting!\n\n", .{}, .{ .color = .red });
                ctx.printer.append("SUGGESTION:\n", .{}, .{ .color = .blue });
                ctx.printer.append(" - Install zig\n $ zep zig install <version>\n\n", .{}, .{});
            },
        }
        return error.ZigNotInstalled;
    };

    zig_version = child.stdout[0 .. child.stdout.len - 1];
    ctx.printer.append("Initing:\n\n", .{}, .{
        .color = .blue,
        .weight = .bold,
    });

    const name = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        "> *Name: ",
        .{
            .required = true,
        },
    );
    const description = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
        "> Description: ",
        .{},
    );
    const license = try Prompt.input(
        ctx.allocator,
        &ctx.printer,
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

pub fn _init(self: *Init) !void {
    self.ctx.printer.append("Initing Zep project...\n", .{}, .{
        .verbosity = 2,
    });

    try self.createFolders();
    try self.createFiles();

    // auto init zig
    try ZigInit.createZigProject(
        &self.ctx.printer,
        self.ctx.allocator,
        self.name,
        self.zig_version,
    );

    self.ctx.printer.append("Finished initing!\n\n", .{}, .{
        .color = .green,
        .verbosity = 2,
    });
}

fn createFolders(_: *Init) !void {
    const cwd = std.fs.cwd();
    _ = cwd.makeDir(Constants.Default.package_files.zep_folder) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn createFiles(self: *Init) !void {
    _ = try Fs.openOrCreateFile(Constants.Default.package_files.injector);

    var lock = Structs.ZepFiles.Lock{};
    lock.root.zig_version = self.zig_version;
    if (!Fs.existsFile(Constants.Default.package_files.lock)) {
        try Json.writePretty(
            self.ctx.allocator,
            Constants.Default.package_files.lock,
            lock,
        );
    }

    const gitignore = ".gitignore";
    const gitignore_main =
        \\zig-out
        \\zep-out
        \\
        \\.zig-cache
        \\.zep
        \\!.zep/injector.zig
    ;

    if (!Fs.existsFile(gitignore)) {
        const f = try Fs.openFile(gitignore);
        _ = try f.write(gitignore_main);
    }
}
