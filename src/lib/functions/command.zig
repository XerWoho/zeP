const std = @import("std");
const builtin = @import("builtin");

pub const Command = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Errors = @import("errors");

const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

const Context = @import("context");

ctx: *Context,

pub fn init(ctx: *Context) Command {
    return Command{
        .ctx = ctx,
    };
}

pub fn add(self: *Command) Errors.Cmd!void {
    self.ctx.logger.info("Adding Command", @src());

    var lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Cmd.ManifestFailed;
    defer lock.deinit();

    var cmds = try std.ArrayList(Structs.ZepFiles.Command).initCapacity(self.ctx.allocator, 10);
    defer cmds.deinit(
        self.ctx.allocator,
    );

    self.ctx.printer.append("Command:\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const command_name = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> *Command Name: ",
        .{
            .required = true,
        },
    ) catch return Errors.Cmd.OutOfMemory;
    defer self.ctx.allocator.free(command_name);
    for (lock.value.root.cmd) |c| {
        if (std.mem.eql(u8, c.name, command_name)) {
            self.ctx.printer.append("\nCommand already exists! Overwrite? (y/N)", .{}, .{
                .color = .red,
                .weight = .bold,
            });

            const answer = Prompt.input(
                self.ctx.allocator,
                &self.ctx.printer,
                "",
                .{},
            ) catch return Errors.Cmd.OutOfMemory;
            if (answer.len == 0 or
                (!std.mem.startsWith(u8, answer, "y") and
                    !std.mem.startsWith(u8, answer, "Y")))
            {
                self.ctx.printer.append("\nOk.\n", .{}, .{});
                return;
            }

            self.ctx.logger.info("Overwriting old command...", @src());
            self.ctx.printer.append("Overwriting...\n\n", .{}, .{
                .color = .white,
                .weight = .bold,
            });

            continue;
        }
        try cmds.append(self.ctx.allocator, c);
    }

    const command = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> *Command: ",
        .{
            .required = true,
        },
    ) catch return Errors.Cmd.OutOfMemory;
    defer self.ctx.allocator.free(command);

    const new_command = Structs.ZepFiles.Command{ .cmd = command, .name = command_name };
    try cmds.append(self.ctx.allocator, new_command);

    lock.value.root.cmd = cmds.items;
    self.ctx.manifest.writeManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
        lock.value,
    ) catch return Errors.Cmd.ManifestFailed;

    self.ctx.printer.append("Successfully added command!\n\n", .{}, .{ .color = .green });
}

pub fn list(self: *Command) Errors.Cmd!void {
    self.ctx.logger.info("Listing Commands", @src());

    var lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Cmd.ManifestFailed;
    defer lock.deinit();

    for (lock.value.root.cmd) |c| {
        self.ctx.printer.append("- Command Name: {s}\n  $ {s}\n\n", .{ c.name, c.cmd }, .{});
    }
}

pub fn remove(self: *Command, key: []const u8) Errors.Cmd!void {
    self.ctx.logger.infof("Removing Command {s}", .{key}, @src());

    var lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Cmd.ManifestFailed;
    defer lock.deinit();

    var cmds = try std.ArrayList(Structs.ZepFiles.Command).initCapacity(self.ctx.allocator, 5);
    defer cmds.deinit(
        self.ctx.allocator,
    );
    for (lock.value.root.cmd) |c| {
        if (std.mem.eql(u8, c.name, key)) continue;
        try cmds.append(self.ctx.allocator, c);
    }
    lock.value.root.cmd = cmds.items;
    self.ctx.manifest.writeManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
        lock.value,
    ) catch return Errors.Cmd.ManifestFailed;

    self.ctx.printer.append("Successfully removed command!\n\n", .{}, .{ .color = .green });
}

pub fn run(self: *Command, key: []const u8) Errors.Cmd!void {
    self.ctx.logger.infof("Running Command {s}", .{key}, @src());

    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Cmd.ManifestFailed;
    defer lock.deinit();

    for (lock.value.root.cmd) |c| {
        if (std.mem.eql(u8, c.name, key)) {
            self.ctx.printer.append("Command was found!\n", .{}, .{ .color = .green });
            var args = try std.ArrayList([]const u8).initCapacity(self.ctx.allocator, 5);
            defer args.deinit(self.ctx.allocator);
            var split = std.mem.splitAny(u8, c.cmd, " ");
            while (split.next()) |arg| {
                try args.append(self.ctx.allocator, arg);
            }
            self.ctx.printer.append("Executing:\n $ {s}\n\n", .{c.cmd}, .{ .color = .green });
            var exec_cmd = std.process.Child.init(args.items, self.ctx.allocator);
            const result = exec_cmd.spawnAndWait() catch return Errors.Cmd.ProcessFailed;
            if (result.Exited > 0) return Errors.Cmd.ProcessFailed;

            self.ctx.printer.append("Finished executing!\n", .{}, .{ .color = .green });
            return;
        }
        continue;
    }
    self.ctx.printer.append("Command not found!\n", .{}, .{ .color = .red });
}
