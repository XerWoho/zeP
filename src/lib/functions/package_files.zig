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

pub fn init(ctx: *Context) PackageFiles {
    return PackageFiles{
        .ctx = ctx,
    };
}

pub fn modify(self: *PackageFiles) !void {
    self.ctx.logger.info("Modifying Package Files", @src());

    var lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();

    self.ctx.printer.append("Lock [Edit]:\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });
    self.ctx.printer.append("(leave empty to keep same)\n\n", .{}, .{ .color = .yellow });
    const author = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Author: ",
        .{
            .initial_value = lock.value.root.author,
        },
    );
    defer self.ctx.allocator.free(author);
    const description = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Description: ",
        .{
            .initial_value = lock.value.root.description,
        },
    );
    defer self.ctx.allocator.free(description);
    const name = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Name: ",
        .{
            .initial_value = lock.value.root.name,
        },
    );
    defer self.ctx.allocator.free(name);
    const license = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> License: ",
        .{
            .initial_value = lock.value.root.license,
        },
    );
    defer self.ctx.allocator.free(license);
    const repo = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Repo: ",
        .{
            .initial_value = lock.value.root.repo,
        },
    );
    defer self.ctx.allocator.free(repo);
    const version = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Version: ",
        .{
            .initial_value = lock.value.root.version,
        },
    );
    defer self.ctx.allocator.free(version);
    const zig_version = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "> Zig Version: ",
        .{
            .initial_value = lock.value.root.zig_version,
        },
    );
    defer self.ctx.allocator.free(zig_version);

    lock.value.root.name = name;
    lock.value.root.license = license;
    lock.value.root.author = author;
    lock.value.root.description = description;
    lock.value.root.repo = repo;
    lock.value.root.version = version;
    lock.value.root.zig_version = zig_version;

    try self.ctx.manifest.writeManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
        lock.value,
    );

    self.ctx.printer.append("\nSuccessfully modified zep.lock!\n\n", .{}, .{ .color = .green });
}
