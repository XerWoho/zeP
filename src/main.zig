const std = @import("std");
const builtin = @import("builtin");
const Constants = @import("constants");
const Utils = @import("utils");
const UtilsPrinter = Utils.UtilsPrinter;
const UtilsSetup = Utils.UtilsSetup;
const UtilsFs = Utils.UtilsFs;

const Init = @import("lib/packages/init.zig");
const Install = @import("lib/packages/install.zig");
const Uninstall = @import("lib/packages/uninstall.zig");
const Clear = @import("lib/packages/clear.zig");
const Purge = @import("lib/packages/purge.zig");
const Zig = @import("lib/zig/zig.zig");
const Zep = @import("lib/zep/zep.zig");
const PreBuilt = @import("lib/preBuilt/prebuilt.zig");
const CustomPackage = @import("lib/packages/custom.zig");

// ------------------------
// Helper Functions
// ------------------------
/// Print the usage and the legend of zeP.
fn printUsage(printer: *UtilsPrinter.Printer) !void {
    try printer.append("\nUsage:\n");
    try printer.append(" Legend:\n  > []  # required\n  > ()  # optional\n\n");
    try printer.append("--- SIMPLE COMMANDS ---\n  zeP version\n  zeP help\n  zeP init\n\n");
    try printer.append("--- PACKAGE COMMANDS ---\n  zeP install (target)\n  zeP uninstall [target]\n");
    try printer.append("  zeP clear [cache|fingerprint]\n  zeP purge [pkg|cache]\n");
    try printer.append("  zeP remove [custom package name]\n  zeP add\n\n");
    try printer.append("--- PREBUILT COMMANDS ---\n  zeP prebuilt [build|use] [name] (target)\n");
    try printer.append("  zeP prebuilt delete [name]\n\n");
    try printer.append("--- ZIG COMMANDS ---\n  zeP zig [uninstall|switch] [version]\n");
    try printer.append("  zeP zig install [version] (target)\n  zeP zig list\n\n");
    try printer.append("--- ZEP COMMANDS ---\n  zeP zep [uninstall|switch] [version]\n");
    try printer.append("  zeP zep install [version] (target)\n  zeP zep list\n\n");
}

/// Fetch the next argument or print an error and exit out of the process.
fn nextArg(args: *std.process.ArgIterator, printer: *UtilsPrinter.Printer, usageMsg: []const u8) ![]const u8 {
    return args.next() orelse blk: {
        try printer.append("Missing argument:\n");
        try printer.append(usageMsg);
        try printer.append("\n");
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

    const data = std.ArrayList([]const u8).init(allocator);
    var printer = try UtilsPrinter.Printer.init(data);
    defer printer.deinit();
    try printer.append("\n");

    const subcommand = args.next() orelse {
        try printer.append("Missing subcommand.\n\n");
        try printUsage(&printer);
        return;
    };

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
        try printer.append("zeP Version 0.1\n\n");
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
            try printer.append("No target specified!\n\n");
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
        var installer = try Install.Installer.init(allocator, &printer, target orelse null);
        defer installer.deinit();
        if (target != null) try installer.install();
        return;
    }

    if (std.mem.eql(u8, subcommand, "uninstall")) {
        const target = try nextArg(&args, &printer, " > zeP uninstall [target]");
        var uninstaller = try Uninstall.Uninstaller.init(allocator, target, &printer);
        defer uninstaller.deinit();
        try uninstaller.uninstall();
        return;
    }

    if (std.mem.eql(u8, subcommand, "clear")) {
        const mode = try nextArg(&args, &printer, " > zeP clear [mode]");
        const CACHE: u8 = 0;
        const FINGERPRINT: u8 = 1;
        var clearer = Clear.Clearer.init();
        if (std.mem.eql(u8, mode, "cache")) {
            try clearer.clear(CACHE);
        } else if (std.mem.eql(u8, mode, "fingerprint")) {
            try clearer.clear(FINGERPRINT);
        } else {
            const invalidMode = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidMode);
        }
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
            const invalidMode = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidMode);
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
                try printer.append("No target specified! Rolling back to default \".\"\n\n");
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
            const invalidMode = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidMode);
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
            const invalidMode = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidMode);
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
            const invalidMode = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidMode);
        }
        return;
    }

    // If we reach here, subcommand is invalid
    const invalidSubcommand = try std.fmt.allocPrint(allocator, "Invalid subcommand: {s}\n\n", .{subcommand});
    try printer.append(invalidSubcommand);
    try printUsage(&printer);
}
