const std = @import("std");
const Context = @import("context");
const Constants = @import("constants");

const Commands = @import("commands.zig").Commands;

const cyan = "\x1b[36m";
const magenta = "\x1b[95m";
const bold = "\x1b[1m";
const closer = "\x1b[0m";

fn printCmd(_cmd: []const u8, desc: []const u8) void {
    std.debug.print(
        "{s}  {s:<35}{s}  {s}\n",
        .{ cyan, _cmd, closer, desc },
    );
}

fn conv(c: []const u8) ?Commands {
    return std.meta.stringToEnum(Commands, c);
}

pub fn help(ctx: *Context) void {
    std.debug.print(
        "\x1b[96m\x1b[1mZep\x1b[0m is a fast, minimal package manager for Zig. \x1b[30m({s}+{s})\x1b[0m\n\n",
        .{ Constants.Default.version, Constants.Default.commit },
    );

    const cmds = ctx.cmds;
    blk: {
        if (cmds.len > 2) {
            const c = cmds[2];
            const command = conv(c) orelse {
                break :blk;
            };
            switch (command) {
                .cache => cache(),
                .package => package(),
                .release => release(),
                .auth => auth(),
                .custom => custom(),
                .inject => inject(),
                .bootstrap => bootstrap(),
                .run => run(),
                .build => build(),
                .cmd => cmd(),
                .prebuilt => prebuilt(),
                .self => self(),
                .zig => zig(),
                .add => install(),
                .install => install(),
                .remove => uninstall(),
                .uninstall => uninstall(),
                else => {
                    break :blk;
                },
            }
            return;
        }
    }

    std.debug.print(
        "Usage:\n  zep <COMMAND> [OPTIONS]\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });

    printCmd("init", "Create a new project");
    printCmd("version", "Print the zep version");
    printCmd("help", "Show help information");
    printCmd("doctor", "Check system and environment health");
    printCmd("config", "Edit lock file from project");
    printCmd("purge", "Remove all installed packages from project");
    printCmd("build", "Build the current project");
    printCmd("run", "Run the current project");
    printCmd("bootstrap", "Initialize dependencies and toolchains");

    printCmd("cache", "Manage cache");
    printCmd("release", "Manage online releases");
    printCmd("package", "Manage online packages");

    std.debug.print("\n{s}{s}Toolchains:{s}\n", .{ bold, magenta, closer });

    printCmd("zig install", "Install a Zig version");
    printCmd("zig uninstall", "Remove a Zig version");
    printCmd("zig switch", "Switch active Zig version");

    std.debug.print("\n", .{});

    printCmd("self install", "Install a specific zep version");
    printCmd("self uninstall", "Remove a zep version");
    printCmd("self switch", "Switch active zep version");
    printCmd("self upgrade", "Upgrade zep to the latest version");

    std.debug.print("\n{s}{s}Auth:{s}\n", .{ bold, magenta, closer });

    printCmd("auth login", "Authenticate with the registry");
    printCmd("auth register", "Create a new account");
    printCmd("auth logout", "Log out of the current account");
    printCmd("auth whoami", "Show the current authenticated user");

    std.debug.print("\n{s}{s}Packages:{s}\n", .{ bold, magenta, closer });

    printCmd("add/install <pkg>", "Install a package");
    printCmd("remove/uninstall <pkg>", "Remove a package");
    printCmd("upgrade [pkg]", "Upgrade dependencies");
    printCmd("list [pkg]", "List package releases");
    printCmd("info <pkg>", "Show package information");

    std.debug.print("\n{s}{s}Advanced:{s}\n", .{ bold, magenta, closer });

    printCmd("custom", "Manage custom packages");
    printCmd("prebuilt", "Manage prebuilt binaries");
    printCmd("cmd", "Manage custom commands");
    printCmd("inject", "Inject configuration into the environment");

    std.debug.print(
        "\nUse 'zep help <command>' for more information on a specific command.\n\n",
        .{},
    );
    if (cmds.len > 2) {
        const c = cmds[2];
        std.debug.print(
            "'zep help {s}' has no help command.\n\n",
            .{c},
        );
    }
}

pub fn cache() void {
    std.debug.print(
        "Usage:\n  cache list|clean|size\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("cache list", "Lists the current packages, cached within the global cache.");
    printCmd("cache clean <pkg>", "Cleans the whole cache size if no package name was defined. If package name is defined all versions of the package will get cleaned, else the specified version will be cleaned only.");
    printCmd("cache size", "Prints the total cache size.");
}
pub fn package() void {
    std.debug.print(
        "Usage:\n  package create|delete|list\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands [Authentication required]:{s}\n", .{ bold, magenta, closer });
    printCmd("package create", "Creates a new package, this is not a release, it is a wrapper in which releases can be created.");
    printCmd("package delete", "Deletes a package.");
    printCmd("package list", "Lists all packages from the authenticated account.");
}
pub fn release() void {
    std.debug.print(
        "Usage:\n  release create|delete|list\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands [Authentication required]:{s}\n", .{ bold, magenta, closer });
    printCmd("release create", "Creates a new release, by compressing the current project with zstd.");
    printCmd("release delete", "Deletes a release.");
    printCmd("release list", "Lists all releases from the authenticated account, and selected package.");
}
pub fn auth() void {
    std.debug.print(
        "Usage:\n  auth login|register|logout|whoami\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("auth login", "Logs into the main zep.run service.");
    printCmd("auth register", "Registers into zep.run, with verification code.");
    printCmd("auth logout", "Logs out of zep.run.");
    printCmd("auth whoami", "Prints the authenticated users data.");
}
pub fn custom() void {
    std.debug.print(
        "Usage:\n  custom add|remove\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("custom add", "Adds a custom package, and stores within the .zep/custom/ folder.");
    printCmd("custom remove <name>", "Removes custom package, name required.");
}
pub fn inject() void {
    std.debug.print(
        "Usage:\n  inject\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("inject", "Sets the modules to which the packages are imported to, or excluded from.");
}
pub fn bootstrap() void {
    std.debug.print(
        "Usage:\n  bootstrap\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("bootstrap --zig=? --pkgs=?", "Creates a new zep project, with the specified tool chains. By default the current zig version is used, else the zig version specified is installed. Packages are to be specified in a single string with commas; --pkgs=clap,mvzr,logly.");
}
pub fn run() void {
    std.debug.print(
        "Usage:\n  run\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("run --target=? --args=?", "Builds and runs the current project, and executes the specified target, which is by default the first executeable found. The args are passed onto the executeable.");
}
pub fn build() void {
    std.debug.print(
        "Usage:\n  build\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("build", "Builds and runs the current project, and stores it via the zep-run/ folder.");
}
pub fn cmd() void {
    std.debug.print(
        "Usage:\n  cmd run|add|remove|list\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("cmd list", "Lists available commands from lock file.");
    printCmd("cmd add", "Adds a new command to the lock file.");
    printCmd("cmd run <name>", "Runs specified command from the lock file.");
    printCmd("cmd remove <name>", "Removes a command from the lock file.");
}
pub fn prebuilt() void {
    std.debug.print(
        "Usage:\n  prebuilt build|use|list\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("prebuilt build <name> <path?>", "Builds the specified path (default '.'), with the given name.");
    printCmd("prebuilt use <name> <path?>", "Uses build, and extracts it to specified path.");
    printCmd("prebuilt delete <name>", "Deletes prebuilt.");
    printCmd("prebuilt list", "Lists all available prebuilts.");
}
pub fn self() void {
    std.debug.print(
        "Usage:\n  self install|uninstall|switch|upgrade\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("self install <version?> <target?>", "Installs the zep with the specified target and version, and switches to it. If no target was specified, the system target will be used. If no version was specified latest is used.");
    printCmd("self uninstall <version> <target?>", "Uninstalls specified zep version.");
    printCmd("self switch <version> <target?>", "Switches to specified, and installed zep version.");
    printCmd("self upgrade <target?>", "Upgrades zep verison to latest.");
}
pub fn zig() void {
    std.debug.print(
        "Usage:\n  zig install|uninstall|switch\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("zig install <version?> <target?>", "Installs the zig with the specified target and version, and switches to it. If no target was specified, the system target will be used. If no version was specified latest is used.");
    printCmd("zig uninstall <version> <target?>", "Uninstalls specified zig version.");
    printCmd("zig switch <version> <target?>", "Switches to specified, and installed zig version.");
    printCmd("self upgrade <target?>", "Upgrades zig verison to latest.");
}
pub fn install() void {
    std.debug.print(
        "Usage:\n  add/install <package>@<version?> <namespace?> <inject?>\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("<package>", "Depends on the given install type. Either owner/repo (or deeper nested eg. in GitLab), or the plain package_name.");
    printCmd("<version?>", "The version of said package, default is 'latest'.");
    printCmd("<namespace?>", "The Installation type / Namespace of package.");
    printCmd("", "(-GH, --github), (-GL, --gitlab), (-CB, --codeberg), (-Z, --zep), (-L, --local)\n");
    printCmd("<inject?>", "Specifies, whether or not the injector command should be displayed, default is false. (-I, --inject)");
}

pub fn uninstall() void {
    std.debug.print(
        "Usage:\n  remove/uninstall <package>@<version?> <namespace?> <global?> <force?>\n\n",
        .{},
    );

    std.debug.print("{s}{s}Commands:{s}\n", .{ bold, magenta, closer });
    printCmd("<package>", "[READ help install]");
    printCmd("<version?>", "[READ help install] => required for global uninstalls");
    printCmd("<namespace?>", "[READ help install] => required for global uninstalls");
    printCmd("<global?>", "Specifies, whether or not to delete a package globally. (-G / --global)");
    printCmd("<force?>", "Forces the uninstallation of a package, even if it is used by other projects. (-F / --force)");
}
