const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

const ZepInstaller = @import("install.zig");
const ZepUninstaller = @import("uninstall.zig");
const ZepLister = @import("list.zig");
const ZepSwitcher = @import("switch.zig");

// ------------------------
// Zep Manager
// ------------------------
pub const Zep = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    installer: ZepInstaller.ZepInstaller,
    uninstaller: ZepUninstaller.ZepUninstaller,
    lister: ZepLister.ZepLister,
    switcher: ZepSwitcher.ZepSwitcher,

    // ------------------------
    // Initialize all submodules
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !Zep {
        const installer = try ZepInstaller.ZepInstaller.init(allocator, printer);
        const uninstaller = try ZepUninstaller.ZepUninstaller.init(allocator, printer);
        const lister = try ZepLister.ZepLister.init(allocator, printer);
        const switcher = try ZepSwitcher.ZepSwitcher.init(allocator, printer);

        return Zep{
            .allocator = allocator,
            .printer = printer,
            .installer = installer,
            .uninstaller = uninstaller,
            .lister = lister,
            .switcher = switcher,
        };
    }

    pub fn deinit(self: *Zep) void {
        self.installer.deinit();
        self.uninstaller.deinit();
        self.switcher.deinit();
        self.lister.deinit();
    }

    // ------------------------
    // Install a Zep version
    // ------------------------
    pub fn install(self: *Zep, targetVersion: []const u8) !void {
        try self.printer.append("Installing version: {s}\n\n", .{targetVersion}, .{});

        const path = try std.fmt.allocPrint(self.allocator, "{s}/v/{s}", .{ Constants.ROOT_ZEP_ZEP_FOLDER, targetVersion });
        defer self.allocator.free(path);
        if (UtilsFs.checkDirExists(path)) {
            try self.printer.append("Zep version already installed.\n", .{}, .{});
            try self.printer.append("Use 'zeP zep switch x.x.x' to update.\n\n", .{}, .{});
            return;
        }

        self.installer.install(targetVersion) catch {
            try self.printer.append("Installing {s} failed...\n\n", .{targetVersion}, .{ .color = 31 });
        };
    }

    // ------------------------
    // Uninstall a Zep version
    // ------------------------
    pub fn uninstall(self: *Zep, targetVersion: []const u8) !void {
        try self.printer.append("Uninstalling version: {s}\n\n", .{targetVersion}, .{});
        const path = try std.fmt.allocPrint(self.allocator, "{s}/v/{s}", .{ Constants.ROOT_ZEP_ZEP_FOLDER, targetVersion });
        defer self.allocator.free(path);

        if (!UtilsFs.checkDirExists(path)) {
            try self.printer.append("Zep version is not installed.\n\n", .{}, .{});
            return;
        }

        self.uninstaller.uninstall(targetVersion) catch {
            try self.printer.append("Uninstalling {s} failed...\n\n", .{targetVersion}, .{ .color = 31 });
        };
    }

    // ------------------------
    // Switch active Zep version
    // ------------------------
    pub fn switchVersion(self: *Zep, targetVersion: []const u8) !void {
        try self.printer.append("Switching version: {s}\n\n", .{targetVersion}, .{});

        const path = try std.fmt.allocPrint(self.allocator, "{s}/v/{s}", .{ Constants.ROOT_ZEP_ZEP_FOLDER, targetVersion });
        defer self.allocator.free(path);

        if (!UtilsFs.checkDirExists(path)) {
            try self.printer.append("Zep version not installed.\n\n", .{}, .{});
            return;
        }

        self.switcher.switchVersion(targetVersion) catch {
            try self.printer.append("Switching to {s} failed...\n\n", .{targetVersion}, .{ .color = 31 });
        };
    }

    // ------------------------
    // List installed Zep versions
    // ------------------------
    pub fn list(self: *Zep) !void {
        self.lister.listVersions() catch {
            try self.printer.append("Listing versions failed...\n\n", .{}, .{ .color = 31 });
        };
    }
};
