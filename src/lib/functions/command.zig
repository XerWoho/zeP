const std = @import("std");
const builtin = @import("builtin");

pub const Command = @This();

const Structs = @import("structs");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

const Context = @import("context");

ctx: *Context,

pub fn init(
    ctx: *Context,
) !Command {
    if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
        try ctx.printer.append("\nNo zep.json file!\n", .{}, .{ .color = .red });
        return error.ManifestNotFound;
    }

    return Command{
        .ctx = ctx,
    };
}

pub fn add(self: *Command) !void {
    var zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

    var cmds = try std.ArrayList(Structs.ZepFiles.CommandPackageJsonStrcut).initCapacity(self.ctx.allocator, 10);
    defer cmds.deinit(
        self.ctx.allocator,
    );
    var stdin_buf: [128]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    try self.ctx.printer.append("--- ADDING COMMAND MODE ---\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const command_name = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> *Command Name: ",
        .{
            .required = true,
        },
    );
    defer self.ctx.allocator.free(command_name);
    for (zep_json.value.cmd) |c| {
        if (std.mem.eql(u8, c.name, command_name)) {
            try self.ctx.printer.append("\nCommand already exists! Overwrite? (Y/n)", .{}, .{
                .color = .red,
                .weight = .bold,
            });

            const input = try Prompt.input(
                self.ctx.allocator,
                &self.ctx.printer,
                stdin,
                "",
                .{},
            );

            if (std.mem.startsWith(u8, input, "n") or std.mem.startsWith(u8, input, "N")) {
                try self.ctx.printer.append("Exiting...\n\n", .{}, .{
                    .color = .white,
                    .weight = .bold,
                });
                return;
            }
            try self.ctx.printer.append("Overwriting...\n\n", .{}, .{
                .color = .white,
                .weight = .bold,
            });

            continue;
        }
        try cmds.append(self.ctx.allocator, c);
    }

    const command = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> *Command: ",
        .{
            .required = true,
        },
    );
    defer self.ctx.allocator.free(command);

    const new_command = Structs.ZepFiles.CommandPackageJsonStrcut{ .cmd = command, .name = command_name };
    try cmds.append(self.ctx.allocator, new_command);

    zep_json.value.cmd = cmds.items;
    try self.ctx.manifest.writeManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
        zep_json.value,
    );

    var zep_lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );
    defer zep_lock.deinit();
    zep_lock.value.root = zep_json.value;
    try self.ctx.manifest.writeManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
        zep_lock.value,
    );
    try self.ctx.printer.append("Successfully added command!\n\n", .{}, .{ .color = .green });
    return;
}

pub fn list(self: *Command) !void {
    var zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

    for (zep_json.value.cmd) |c| {
        try self.ctx.printer.append("- Command Name: {s}\n  $ {s}\n\n", .{ c.name, c.cmd }, .{});
    }
    return;
}

pub fn remove(self: *Command, key: []const u8) !void {
    var zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

    var cmds = try std.ArrayList(Structs.ZepFiles.CommandPackageJsonStrcut).initCapacity(self.ctx.allocator, 5);
    defer cmds.deinit(
        self.ctx.allocator,
    );
    for (zep_json.value.cmd) |c| {
        if (std.mem.eql(u8, c.name, key)) continue;
        try cmds.append(self.ctx.allocator, c);
    }
    zep_json.value.cmd = cmds.items;
    try self.ctx.manifest.writeManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
        zep_json.value,
    );

    var zep_lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
    );
    defer zep_lock.deinit();
    zep_lock.value.root = zep_json.value;
    try self.ctx.manifest.writeManifest(
        Structs.ZepFiles.PackageLockStruct,
        Constants.Extras.package_files.lock,
        zep_lock.value,
    );

    try self.ctx.printer.append("Successfully removed command!\n\n", .{}, .{ .color = .green });
    return;
}

pub fn run(self: *Command, key: []const u8) !void {
    const zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

    for (zep_json.value.cmd) |c| {
        if (std.mem.eql(u8, c.name, key)) {
            try self.ctx.printer.append("Command was found!\n", .{}, .{ .color = .green });
            var args = try std.ArrayList([]const u8).initCapacity(self.ctx.allocator, 5);
            defer args.deinit(self.ctx.allocator);
            var split = std.mem.splitAny(u8, c.cmd, " ");
            while (split.next()) |arg| {
                try args.append(self.ctx.allocator, arg);
            }
            try self.ctx.printer.append("Executing:\n $ {s}\n\n", .{c.cmd}, .{ .color = .green });
            var exec_cmd = std.process.Child.init(args.items, self.ctx.allocator);
            _ = exec_cmd.spawnAndWait() catch {};

            try self.ctx.printer.append("\nFinished executing!\n", .{}, .{ .color = .green });
            return;
        }
        continue;
    }
    try self.ctx.printer.append("\nCommand not found!\n", .{}, .{ .color = .red });
    return;
}
