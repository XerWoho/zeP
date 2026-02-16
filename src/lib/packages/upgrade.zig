const std = @import("std");

pub const Upgrader = @This();

const Locales = @import("locales");
const Constants = @import("constants");
const Structs = @import("structs");

const Errors = @import("errors");

const Installer = @import("install.zig");
const Context = @import("context");

ctx: *Context,

pub fn init(ctx: *Context) Upgrader {
    return Upgrader{
        .ctx = ctx,
    };
}

pub fn deinit(_: *Upgrader) void {}

pub fn upgrade(self: *Upgrader) Errors.Installable!void {
    self.ctx.logger.info("Upgrading packages...", @src());

    const prev_verbosity = Locales.VERBOSITY_MODE;
    Locales.VERBOSITY_MODE = 0;

    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Installable.ManifestFailed;
    defer lock.deinit();

    var installer = Installer.init(self.ctx);
    for (lock.value.packages) |package| {
        const name = switch (package.namespace) {
            .github => try std.fmt.allocPrint(self.ctx.allocator, "{s}/{s}", .{
                package.author,
                package.name,
            }),
            else => try self.ctx.allocator.dupe(u8, package.name),
        };
        defer self.ctx.allocator.free(name);

        self.ctx.printer.append(
            " > Upgrading - {s}",
            .{name},
            .{ .verbosity = 0 },
        );

        // if no version was specified it gets the
        // latest version
        installer.installPackage(
            name,
            null,
            package.namespace,
            false,
        ) catch |err| {
            switch (err) {
                error.AlreadyInstalled => {
                    self.ctx.printer.append(
                        " >> already latest!\n",
                        .{},
                        .{ .verbosity = 0, .color = .green },
                    );
                    continue;
                },
                else => {
                    self.ctx.printer.append(
                        "  ! [ERROR] Failed to upgrade - {s} [{any}]...\n",
                        .{ name, err },
                        .{ .verbosity = 0, .color = .red },
                    );
                    continue;
                },
            }
        };

        self.ctx.printer.append(
            " >> upgraded!\n",
            .{},
            .{ .verbosity = 0, .color = .green },
        );
        continue;
    }

    Locales.VERBOSITY_MODE = prev_verbosity;
}
