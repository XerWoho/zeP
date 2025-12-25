const std = @import("std");
const Context = @import("context");

pub fn help(ctx: *Context) void {
    _ = ctx;
    std.debug.print("Usage:\n", .{});
    std.debug.print(" Legend:\n  > []  # required\n  > ()  # optional\n\n", .{});
    std.debug.print(
        "--- SIMPLE COMMANDS ---\n  zep version\n  zep help\n  zep paths\n  zep doctor\n\n",
        .{},
    );
    std.debug.print(
        "--- BUILD COMMANDS ---\n  zep runner (--target <target>) (--args <args>)\n  zep build\n  zep bootstrap (--zig <zig-version>) (--deps <package1,package2>)\n  zep new <name>\n\n",
        .{},
    );
    std.debug.print(
        "--- MANIFEST COMMANDS ---\n  zep init\n  zep manifest modify\n  zep manifest sync\n\n",
        .{},
    );
    std.debug.print(
        "--- CMD COMMANDS ---\n  zep cmd run [cmd]\n  zep cmd add\n  zep cmd remove <cmd>\n  zep cmd list\n\n",
        .{},
    );
    std.debug.print(
        "--- PACKAGE COMMANDS ---\n  zep install (target)@(version)\n  zep uninstall [target]\n  zep info [target]@[version]\n",
        .{},
    );
    std.debug.print(
        "  zep purge\n  zep cache [list|clean|size] (package_id)\n  zep inject\n\n",
        .{},
    );
    std.debug.print(
        "--- CUSTOM PACKAGE COMMANDS ---\n  zep package list [target]\n  zep package info [target]\n  zep package remove [custom package name]\n  zep package add\n\n",
        .{},
    );
    std.debug.print(
        "--- PREBUILT COMMANDS ---\n  zep prebuilt [build|use] [name] (target)\n",
        .{},
    );
    std.debug.print(
        "  zep prebuilt delete [name]\n  zep prebuilt list\n\n",
        .{},
    );
    std.debug.print(
        "--- ZIG COMMANDS ---\n  zep zig [uninstall|switch] [version]\n",
        .{},
    );
    std.debug.print(
        "  zep zig install [version] (target)\n  zep zig list\n  zep zig prune\n\n",
        .{},
    );
    std.debug.print(
        "--- ZEP COMMANDS ---\n  zep zep [uninstall|switch] [version]\n",
        .{},
    );
    std.debug.print(
        "  zep zep install [version] (target)\n  zep zep list\n  zep zep prune\n\n",
        .{},
    );
}
