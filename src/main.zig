const std = @import("std");
const builtin = @import("builtin");
const Constants = @import("constants");
const Structs = @import("structs");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsSetup = Utils.UtilsSetup;
const UtilsFs = Utils.UtilsFs;
const UtilsManifest = Utils.UtilsManifest;

const Init = @import("lib/packages/init.zig");
const Install = @import("lib/packages/install.zig");
const Uninstall = @import("lib/packages/uninstall.zig");
const List = @import("lib/packages/list.zig");
const Purge = @import("lib/packages/purge.zig");
const Zig = @import("lib/zig/zig.zig");
const Zep = @import("lib/zep/zep.zig");
const PreBuilt = @import("lib/preBuilt/preBuilt.zig");
const CustomPackage = @import("lib/packages/custom.zig");

// ------------------------
// Helper Functions
// ------------------------
/// Print the usage and the legend of zeP.
fn printUsage(printer: *UtilsPrinter.Printer) !void {
    try printer.append("\nUsage:\n", .{}, .{});
    try printer.append(" Legend:\n  > []  # required\n  > ()  # optional\n\n", .{}, .{});
    try printer.append("--- SIMPLE COMMANDS ---\n  zeP version\n  zeP help\n  zeP init\n\n", .{}, .{});
    try printer.append("--- PACKAGE COMMANDS ---\n  zeP install (target)@(version)\n  zeP uninstall [target]\n", .{}, .{});
    try printer.append("  zeP purge [pkg|cache]\n", .{}, .{});
    try printer.append("  zeP remove [custom package name]\n  zeP add\n zeP list [target]\n\n", .{}, .{});
    try printer.append("--- PREBUILT COMMANDS ---\n  zeP prebuilt [build|use] [name] (target)\n", .{}, .{});
    try printer.append("  zeP prebuilt delete [name]\n\n", .{}, .{});
    try printer.append("--- ZIG COMMANDS ---\n  zeP zig [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zeP zig install [version] (target)\n  zeP zig list\n\n", .{}, .{});
    try printer.append("--- ZEP COMMANDS ---\n  zeP zep [uninstall|switch] [version]\n", .{}, .{});
    try printer.append("  zeP zep install [version] (target)\n  zeP zep list\n\n", .{}, .{});
}

/// Fetch the next argument or print an error and exit out of the process.
fn nextArg(args: *std.process.ArgIterator, printer: *UtilsPrinter.Printer, usageMsg: []const u8) ![]const u8 {
    return args.next() orelse blk: {
        try printer.append("Missing argument:\n{s}\n", .{usageMsg}, .{});
        std.process.exit(1);
        break :blk "";
    };
}

/// Resolve default target if no target specified
fn resolveDefaultTarget() []const u8 {
    if (builtin.target.os.tag == .windows) return Constants.DEFAULT_TARGET_WINDOWS;
    return Constants.DEFAULT_TARGET_LINUX;
}

// ------------------------
// Main Function
// ------------------------

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name

    const data = std.ArrayList(Structs.PrinterData).init(allocator);
    var printer = try UtilsPrinter.Printer.init(data);
    defer printer.deinit();
    try printer.append("\n", .{}, .{});

    const subcommand = args.next() orelse {
        try printer.append("Missing subcommand.\n\n", .{}, .{});
        try printUsage(&printer);
        return;
    };

    if (builtin.os.tag == .linux) {
        const pid = std.os.linux.geteuid();
        if (pid != 0) {
            try printer.append("Root permissions required for this action!\n", .{}, .{ .color = 31 });
            return;
        }
    }

    // ------------------------
    // Schema check
    // ------------------------
    // First verify that we are in zeP project
    //-------------------------
    if (UtilsFs.checkFileExists(Constants.ZEP_LOCK_PACKAGE_FILE) and
        UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE) and
        UtilsFs.checkDirExists(Constants.ZEP_FOLDER))
    {
        const lock = try UtilsManifest.readManifest(Structs.PackageLockStruct, allocator, Constants.ZEP_LOCK_PACKAGE_FILE);
        defer lock.deinit();
        if (lock.value.schema != Constants.ZEP_LOCK_SCHEMA_VERSION) {
            try printer.append("Lock file schema is NOT matching with zeP version.\nConsider removing them, and re-initing!\n", .{}, .{});
            return;
        }
    }

    // ------------------------
    // Simple commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "setup")) {
        try UtilsSetup.setup(&printer);
        return;
    }
    if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage(&printer);
        return;
    }
    if (std.mem.eql(u8, subcommand, "version")) {
        try printer.append("zeP Version 0.3\n\n", .{}, .{});
        return;
    }

    // ------------------------
    // Custom package commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "add")) {
        var custom = CustomPackage.CustomPackage.init(allocator, &printer);
        try custom.requestPackage();
        return;
    }
    if (std.mem.eql(u8, subcommand, "remove")) {
        const target = args.next();
        var custom = CustomPackage.CustomPackage.init(allocator, &printer);
        if (target == null) {
            try printer.append("No target specified!\n\n", .{}, .{});
            return;
        }
        try custom.removePackage(target.?);
        return;
    }

    // ------------------------
    // Package management commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "init")) {
        var initter = try Init.Init.init(allocator);
        try initter.commitInit();
        return;
    }

    if (std.mem.eql(u8, subcommand, "install")) {
        const target = args.next();
        if (target) |package| {
            var split = std.mem.splitScalar(u8, package, '@');
            const packageName = split.first();
            const packageVersion = split.next();

            var installer = try Install.Installer.init(allocator, &printer, packageName, packageVersion);
            defer installer.deinit();
            installer.install() catch |err| {
                switch (err) {
                    error.AlreadyInstalled => {
                        try printer.append("Already installed!\n\n", .{}, .{ .color = 33 });
                    },
                    else => {
                        try printer.append("Installing {s} has failed...\n\n", .{package}, .{ .color = 31 });
                    },
                }
            };
        } else {
            var installer = try Install.Installer.init(allocator, &printer, null, null);
            defer installer.deinit();
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        const target = args.next();
        if (target) |package| {
            var split = std.mem.splitScalar(u8, package, '@');
            const packageName = split.first();
            var lister = try List.Lister.init(allocator, &printer, packageName);
            try lister.list();
        } else {
            try printer.append("Missing argument;\nzeP list [target]\n\n", .{}, .{ .color = 31 });
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "uninstall")) {
        const target = try nextArg(&args, &printer, " > zeP uninstall [target]");
        var split = std.mem.splitScalar(u8, target, '@');
        const packageName = split.first();

        var uninstaller = try Uninstall.Uninstaller.init(allocator, packageName, &printer);
        defer uninstaller.deinit();
        uninstaller.uninstall() catch {
            try printer.append("Installing {s} has failed...\n\n", .{packageName}, .{ .color = 31 });
        };
        return;
    }

    if (std.mem.eql(u8, subcommand, "purge")) {
        const mode = try nextArg(&args, &printer, " > zeP purge [pkg|cache]");
        var purger = try Purge.Purger.init(allocator, &printer);
        if (std.mem.eql(u8, mode, "pkg")) {
            try purger.purgePkgs();
        } else if (std.mem.eql(u8, mode, "cache")) {
            try purger.purgeCache();
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    // ------------------------
    // Prebuilt commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "prebuilt")) {
        const mode = try nextArg(&args, &printer, " > zeP prebuilt [build|use|delete] [name]");
        var prebuilt = try PreBuilt.PreBuilt.init(allocator, &printer);

        if (std.mem.eql(u8, mode, "build") or std.mem.eql(u8, mode, "use")) {
            const name = try nextArg(&args, &printer, " > zeP prebuilt {build|use} [name] [target?]");
            const target = args.next() orelse blk: {
                try printer.append("No target specified! Rolling back to default \".\"\n\n", .{}, .{});
                break :blk ".";
            };
            if (std.mem.eql(u8, mode, "build")) {
                try prebuilt.buildBuilt(name, target);
            } else {
                try prebuilt.useBuilt(name, target);
            }
        } else if (std.mem.eql(u8, mode, "delete")) {
            const name = try nextArg(&args, &printer, " > zeP prebuilt delete [name]");
            try prebuilt.deleteBuilt(name);
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    // ------------------------
    // Zig commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "zig")) {
        const mode = try nextArg(&args, &printer, " > zeP zig [install|switch|uninstall|list] [version]");
        var zig = try Zig.Zig.init(allocator, &printer);
        defer zig.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zeP zig {install|switch|uninstall} [version] [target?]");
            const target = args.next() orelse resolveDefaultTarget();
            if (std.mem.eql(u8, mode, "install")) {
                try zig.install(version, target);
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                try zig.uninstall(version, target);
            } else {
                try zig.switchVersion(version, target);
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            try zig.list();
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    // ------------------------
    // Zep commands
    // ------------------------
    if (std.mem.eql(u8, subcommand, "zep")) {
        const mode = try nextArg(&args, &printer, " > zeP zep [install|switch|uninstall|list] [version]");
        var zep = try Zep.Zep.init(allocator, &printer);
        defer zep.deinit();

        if (std.mem.eql(u8, mode, "install") or std.mem.eql(u8, mode, "uninstall") or std.mem.eql(u8, mode, "switch")) {
            const version = try nextArg(&args, &printer, " > zeP zep {install|switch|uninstall} [version]");
            if (std.mem.eql(u8, mode, "install")) {
                try zep.install(version);
            } else if (std.mem.eql(u8, mode, "uninstall")) {
                try zep.uninstall(version);
            } else {
                try zep.switchVersion(version);
            }
        } else if (std.mem.eql(u8, mode, "list")) {
            try zep.list();
        } else {
            try printer.append("Invalid mode: {s}\n\n", .{mode}, .{});
        }
        return;
    }

    // If we reach here, subcommand is invalid
    try printer.append("Invalid subcommand: {s}\n\n", .{subcommand}, .{});
    try printUsage(&printer);
}
