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

fn printUsage(printer: *UtilsPrinter.Printer) !void {
    try printer.append("Usage:\n");
    try printer.append("  zeP version\n");
    try printer.append("  zeP help\n");
    try printer.append("  zeP init\n");
    try printer.append("  zeP install [target]\n");
    try printer.append("  zeP uninstall [target]\n");
    try printer.append("  zeP clear [cache|fingerprint]\n");
    try printer.append("  zeP purge [pkg|cache]\n");
    try printer.append("  zeP zig [install|uninstall|switch|list]\n\n");
}

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

    if (std.mem.eql(u8, subcommand, "setup")) {
        try UtilsSetup.setup(&printer);
        return;
    }

    inline for ([_][]const u8{ "version", "help", "init", "install", "uninstall", "clear", "purge", "zig" }) |cmd| {
        if (std.mem.eql(u8, subcommand, cmd)) break;
    } else {
        const invalidSC = try std.fmt.allocPrint(allocator, "Invalid subcommand: {s}\n\n", .{subcommand});
        try printer.append(invalidSC);
        try printUsage(&printer);
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

    if (std.mem.eql(u8, subcommand, "init")) {
        var initter = try Init.Init.init(allocator);
        try initter.commitInit();
    } else if (std.mem.eql(u8, subcommand, "install")) {
        const target = args.next();
        if (target) |_| {
            var installer = try Install.Installer.init(allocator, &printer, target);
            try installer.install();
        } else {
            _ = try Install.Installer.init(allocator, &printer, null);
        }
    } else if (std.mem.eql(u8, subcommand, "uninstall")) {
        const target = args.next() orelse {
            try printer.append("Missing argument:\n > zeP uninstall [target]\n\n");
            return;
        };

        var uninstaller = try Uninstall.Uninstaller.init(allocator, target, &printer);
        try uninstaller.uninstall();
    } else if (std.mem.eql(u8, subcommand, "clear")) {
        const mode = args.next() orelse {
            try printer.append("Missing argument:\n > zeP clear [mode]\n\n");
            return;
        };
        const CACHE: u8 = 0;
        const FINGERPRINT: u8 = 1;

        var clearer = Clear.Clearer.init();
        if (std.mem.eql(u8, mode, "cache")) {
            try clearer.clear(CACHE);
        } else if (std.mem.eql(u8, mode, "fingerprint")) {
            try clearer.clear(FINGERPRINT);
        } else {
            const invalidM = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidM);
        }
    } else if (std.mem.eql(u8, subcommand, "purge")) {
        const mode = args.next() orelse {
            try printer.append("Missing argument:\n > zeP purge [pkg|cache]\n\n");
            return;
        };

        var purger = try Purge.Purger.init(allocator, &printer);
        if (std.mem.eql(u8, mode, "pkg")) {
            try purger.purgePkgs();
        } else if (std.mem.eql(u8, mode, "cache")) {
            try purger.purgeCache();
        } else {
            const invalidM = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidM);
        }
    } else if (std.mem.eql(u8, subcommand, "zig")) {
        const mode = args.next() orelse {
            try printer.append("Missing argument:\n > zeP zig [install|switch|uninstall] [version]\n\n");
            return;
        };

        var zig = try Zig.Zig.init(allocator, &printer);
        defer zig.deinit();
        if (std.mem.eql(u8, mode, "install")) {
            const targetVersion = args.next() orelse {
                try printer.append("Missing argument:\n > zeP zig install [version/latest] [target?]\n\n");
                return;
            };

            const targetSrc = args.next() orelse blk: {
                try printer.append("No target specified, rolling back to default targets.\n");
                if (builtin.target.os.tag == .windows) break :blk Constants.DEFAULT_TARGET_WINDOWS;
                break :blk Constants.DEFAULT_TARGET_LINUX;
            };

            try zig.install(targetVersion, targetSrc);
        } else if (std.mem.eql(u8, mode, "uninstall")) {
            const targetVersion = args.next() orelse {
                try printer.append("Missing argument:\n > zeP zig uninstall [version] [target?]\n\n");
                return;
            };

            const targetSrc = args.next() orelse blk: {
                try printer.append("No target specified, rolling back to default targets.\n");
                if (builtin.target.os.tag == .windows) break :blk Constants.DEFAULT_TARGET_WINDOWS;
                break :blk Constants.DEFAULT_TARGET_LINUX;
            };

            try zig.uninstall(targetVersion, targetSrc);
        } else if (std.mem.eql(u8, mode, "switch")) {
            const targetVersion = args.next() orelse {
                try printer.append("Missing argument:\n > zeP zig switch [version] [target?]\n\n");
                return;
            };

            const targetSrc = args.next() orelse blk: {
                try printer.append("No target specified, rolling back to default targets.\n");
                if (builtin.target.os.tag == .windows) break :blk Constants.DEFAULT_TARGET_WINDOWS;
                break :blk Constants.DEFAULT_TARGET_LINUX;
            };

            try zig.switchV(targetVersion, targetSrc);
        } else if (std.mem.eql(u8, mode, "list")) {
            try zig.list();
        } else {
            const invalidM = try std.fmt.allocPrint(allocator, "Invalid mode: {s}\n\n", .{mode});
            try printer.append(invalidM);
        }
    }
}
