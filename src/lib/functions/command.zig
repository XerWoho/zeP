const std = @import("std");
const builtin = @import("builtin");

const Structs = @import("structs");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

pub const Command = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !Command {
        const runner = Command{ .allocator = allocator, .printer = printer };
        if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
            try printer.append("\nNo zep.json file!\n", .{}, .{ .color = .red });
            return error.ManifestNotFound;
        }

        return runner;
    }

    pub fn add(self: *Command) !void {
        var zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        var cmds = std.ArrayList(Structs.ZepFiles.CommandPackageJsonStrcut).init(self.allocator);
        defer cmds.deinit();
        const stdin = std.io.getStdIn().reader();

        try self.printer.append("--- ADDING COMMAND MODE ---\n\n", .{}, .{
            .color = .yellow,
            .weight = .bold,
        });

        const command_name = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> *Command Name: ",
            .{
                .required = true,
            },
        );
        defer self.allocator.free(command_name);
        for (zep_json.value.cmd) |c| {
            if (std.mem.eql(u8, c.name, command_name)) {
                try self.printer.append("\nCommand already exists! Overwrite? (Y/n)", .{}, .{
                    .color = .red,
                    .weight = .bold,
                });

                const input = try Prompt.input(
                    self.allocator,
                    self.printer,
                    stdin,
                    "",
                    .{},
                );

                if (std.mem.startsWith(u8, input, "n") or std.mem.startsWith(u8, input, "N")) {
                    try self.printer.append("Exiting...\n\n", .{}, .{
                        .color = .white,
                        .weight = .bold,
                    });
                    return;
                }
                try self.printer.append("Overwriting...\n\n", .{}, .{
                    .color = .white,
                    .weight = .bold,
                });

                continue;
            }
            try cmds.append(c);
        }

        const command = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            "> *Command: ",
            .{
                .required = true,
            },
        );
        defer self.allocator.free(command);

        const new_command = Structs.ZepFiles.CommandPackageJsonStrcut{ .cmd = command, .name = command_name };
        try cmds.append(new_command);

        zep_json.value.cmd = cmds.items;
        try Manifest.writeManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest, zep_json.value);

        var zep_lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer zep_lock.deinit();
        zep_lock.value.root = zep_json.value;
        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock, zep_lock.value);
        try self.printer.append("Successfully added command!\n\n", .{}, .{ .color = .green });
        return;
    }

    pub fn list(self: *Command) !void {
        var zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        for (zep_json.value.cmd) |c| {
            try self.printer.append("- Command Name: {s}\n  $ {s}\n\n", .{ c.name, c.cmd }, .{});
        }
        return;
    }

    pub fn remove(self: *Command, key: []const u8) !void {
        var zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        var cmds = std.ArrayList(Structs.ZepFiles.CommandPackageJsonStrcut).init(self.allocator);
        defer cmds.deinit();
        for (zep_json.value.cmd) |c| {
            if (std.mem.eql(u8, c.name, key)) continue;
            try cmds.append(c);
        }
        zep_json.value.cmd = cmds.items;
        try Manifest.writeManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest, zep_json.value);

        var zep_lock = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer zep_lock.deinit();
        zep_lock.value.root = zep_json.value;
        try Manifest.writeManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock, zep_lock.value);

        try self.printer.append("Successfully removed command!\n\n", .{}, .{ .color = .green });
        return;
    }

    pub fn run(self: *Command, key: []const u8) !void {
        const zep_json = try Manifest.readManifest(Structs.ZepFiles.PackageJsonStruct, self.allocator, Constants.Extras.package_files.manifest);
        defer zep_json.deinit();

        for (zep_json.value.cmd) |c| {
            if (std.mem.eql(u8, c.name, key)) {
                try self.printer.append("Command was found!\n", .{}, .{ .color = .green });
                var args = std.ArrayList([]const u8).init(self.allocator);
                defer args.deinit();
                var split = std.mem.splitAny(u8, c.cmd, " ");
                while (split.next()) |arg| {
                    try args.append(arg);
                }
                try self.printer.append("Executing:\n $ {s}\n\n", .{c.cmd}, .{ .color = .green });
                var exec_cmd = std.process.Child.init(args.items, self.allocator);
                _ = exec_cmd.spawnAndWait() catch {};

                try self.printer.append("\nFinished executing!\n", .{}, .{ .color = .green });
                return;
            }
            continue;
        }
        try self.printer.append("\nCommand not found!\n", .{}, .{ .color = .red });
        return;
    }
};
