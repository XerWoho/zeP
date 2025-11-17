const std = @import("std");
const builtin = @import("builtin");

const Manifest = @import("lib/manifest.zig");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

/// Installer for Zep versions
pub const ZepInstaller = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    // ------------------------
    // Initialize ZepInstaller
    // ------------------------
    pub fn init(
        allocator: std.mem.Allocator,
        printer: *UtilsPrinter.Printer,
    ) !ZepInstaller {
        return ZepInstaller{
            .allocator = allocator,
            .printer = printer,
        };
    }

    // ------------------------
    // Deinitialize
    // ------------------------
    pub fn deinit(_: *ZepInstaller) void {
        // currently no deinit required
    }

    // ------------------------
    // Public install function
    // ------------------------
    pub fn install(self: *ZepInstaller, version: []const u8) !void {
        if (builtin.os.tag == .windows) {
            // Windows: use powershell script to modify PATH
            const argv = &[_][]const u8{ "iex", "((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/XerWoho/zeP/refs/heads/main/scripts/installer/installer.ps1'))", version };
            var process = std.process.Child.init(argv, self.allocator);
            try process.spawn();
            _ = try process.wait();
            _ = try process.kill();
        } else {
            const argv = &[_][]const u8{ "curl", "-s", "https://raw.githubusercontent.com/XerWoho/zeP/refs/heads/main/scripts/installer/installer.sh", "|", "sudo", "bash" };
            var process = std.process.Child.init(argv, self.allocator);
            try process.spawn();
            _ = try process.wait();
            _ = try process.kill();
        }
    }
};
