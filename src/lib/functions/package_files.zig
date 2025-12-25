const std = @import("std");
const builtin = @import("builtin");

pub const PackageFiles = @This();

const Structs = @import("structs");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Manifest = @import("core").Manifest;

const Context = @import("context");

ctx: *Context,

pub fn init(ctx: *Context) !PackageFiles {
    if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
        try ctx.printer.append("\nNo zep.json file!\n", .{}, .{ .color = .red });
        return error.ManifestMissing;
    }

    return PackageFiles{
        .ctx = ctx,
    };
}

pub fn modify(self: *PackageFiles) !void {
    var zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

    var stdin_buf: [128]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;
    try self.ctx.printer.append("--- MODIFYING JSON MODE ---\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });
    try self.ctx.printer.append("(leave empty to keep same)\n\n", .{}, .{ .color = .yellow });
    const author = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Author: ",
        .{
            .initial_value = zep_json.value.author,
        },
    );
    defer self.ctx.allocator.free(author);
    const description = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Description: ",
        .{
            .initial_value = zep_json.value.description,
        },
    );
    defer self.ctx.allocator.free(description);
    const name = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Name: ",
        .{
            .initial_value = zep_json.value.name,
        },
    );
    defer self.ctx.allocator.free(name);
    const license = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> License: ",
        .{
            .initial_value = zep_json.value.license,
        },
    );
    defer self.ctx.allocator.free(license);
    const repo = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Repo: ",
        .{
            .initial_value = zep_json.value.repo,
        },
    );
    defer self.ctx.allocator.free(repo);
    const version = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Version: ",
        .{
            .initial_value = zep_json.value.version,
        },
    );
    defer self.ctx.allocator.free(version);
    const zig_version = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        stdin,
        "> Zig Version: ",
        .{
            .initial_value = zep_json.value.zig_version,
        },
    );
    defer self.ctx.allocator.free(zig_version);

    zep_json.value.name = name;
    zep_json.value.license = license;
    zep_json.value.author = author;
    zep_json.value.description = description;
    zep_json.value.repo = repo;
    zep_json.value.version = version;
    zep_json.value.zig_version = zig_version;

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
    try self.ctx.printer.append("\nSuccessfully modified zep.json!\n\n", .{}, .{ .color = .green });
    return;
}

pub fn sync(self: *PackageFiles) !void {
    var zep_json = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.PackageJsonStruct,
        Constants.Extras.package_files.manifest,
    );
    defer zep_json.deinit();

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

    try self.ctx.printer.append("Successfully moved zep.json into zep.lock!\n\n", .{}, .{ .color = .green });
    return;
}
