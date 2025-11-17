const std = @import("std");

const MAX_JSON_SIZE = 1028 * 1028 * 50; // Maximum size for JSON download

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

const ZigInstaller = @import("install.zig");
const ZigUninstaller = @import("uninstall.zig");
const ZigLister = @import("list.zig");
const ZigSwitcher = @import("switch.zig");

const Manifest = @import("lib/manifest.zig");

// ------------------------
// Version Data
// ------------------------
pub const Version = struct {
    path: []const u8,
    tarball: []const u8,
    name: []const u8,
    version: []const u8,
};

// ------------------------
// Zig Manager
// ------------------------
pub const Zig = struct {
    allocator: std.mem.Allocator,
    printer: *UtilsPrinter.Printer,

    installer: ZigInstaller.ZigInstaller,
    uninstaller: ZigUninstaller.ZigUninstaller,
    lister: ZigLister.ZigLister,
    switcher: ZigSwitcher.ZigSwitcher,

    // ------------------------
    // Initialize all submodules
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !Zig {
        const installer = try ZigInstaller.ZigInstaller.init(allocator, printer);
        const uninstaller = try ZigUninstaller.ZigUninstaller.init(allocator, printer);
        const lister = try ZigLister.ZigLister.init(allocator, printer);
        const switcher = try ZigSwitcher.ZigSwitcher.init(allocator, printer);

        return Zig{
            .allocator = allocator,
            .printer = printer,
            .installer = installer,
            .uninstaller = uninstaller,
            .lister = lister,
            .switcher = switcher,
        };
    }

    pub fn deinit(self: *Zig) void {
        self.installer.deinit();
        self.uninstaller.deinit();
        self.switcher.deinit();
        self.lister.deinit();
    }

    // ------------------------
    // Fetch version metadata from Zig JSON
    // ------------------------
    fn fetchVersion(self: *Zig, targetVersion: []const u8) !std.json.Value {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var buffer: [4096]u8 = undefined;
        const uri = try std.Uri.parse(Constants.ZIG_V_JSON);
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &buffer });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();

        var reader = req.reader();
        const body = try reader.readAllAlloc(self.allocator, MAX_JSON_SIZE);
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        const obj = parsed.value.object;

        if (std.mem.eql(u8, targetVersion, "latest") or targetVersion.len == 0) {
            return obj.get("master") orelse return error.NotFound;
        }
        return obj.get(targetVersion) orelse return error.NotFound;
    }

    // ------------------------
    // Get structured version info
    // ------------------------
    pub fn getVersion(self: *Zig, targetVersion: []const u8, target: []const u8) !Version {
        try self.printer.append("Getting target version...\n");

        const versionData = self.fetchVersion(targetVersion) catch {
            try self.printer.append("Version not found...\n\n");
            std.process.exit(0);
        };

        const obj = versionData.object;
        const urlVal = obj.get(target);
        if (urlVal == null) {
            try self.printer.append("Target not found...\n\n");
            return Version{ .name = "", .path = "", .tarball = "", .version = "" };
        }

        const tarballVal = urlVal.?.object.get("tarball");
        const tarball = tarballVal.?.string;

        var resolvedVersion: []const u8 = targetVersion;
        if (obj.get("version")) |v| {
            resolvedVersion = v.string;
        }

        // Parse name from tarball URL
        const prefix = "https://ziglang.org/download/";
        const skipLen = prefix.len + targetVersion.len + 1;
        const name = tarball[skipLen .. tarball.len - 4];

        const path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/d/{s}/{s}",
            .{ Constants.ROOT_ZEP_ZIG_FOLDER, resolvedVersion, target },
        );

        return Version{
            .path = path,
            .name = name,
            .version = resolvedVersion,
            .tarball = tarball,
        };
    }

    // ------------------------
    // Install a Zig version
    // ------------------------
    pub fn install(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Installing version: ");
        try self.printer.append(targetVersion);
        try self.printer.append("\nWith target: ");
        try self.printer.append(target);
        try self.printer.append("\n\n");

        const version = try self.getVersion(targetVersion, target);
        if (version.path.len == 0) return;

        if (try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version already installed.\n");
            try self.printer.append("Use 'zeP zig switch x.x.x' to update.\n\n");
            return;
        }
        try self.installer.install(version.name, version.tarball, version.version, target);
    }

    // ------------------------
    // Uninstall a Zig version
    // ------------------------
    pub fn uninstall(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Uninstalling version: ");
        try self.printer.append(targetVersion);
        try self.printer.append("\nWith target: ");
        try self.printer.append(target);
        try self.printer.append("\n\n");

        const version = try self.getVersion(targetVersion, target);
        if (!try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version is not installed.\n\n");
            return;
        }

        try self.uninstaller.uninstall(version.path);
    }

    // ------------------------
    // Switch active Zig version
    // ------------------------
    pub fn switchVersion(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Switching version: ");
        try self.printer.append(targetVersion);
        try self.printer.append("\nWith target: ");
        try self.printer.append(target);
        try self.printer.append("\n\n");

        const version = try self.getVersion(targetVersion, target);
        if (!try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version not installed.\n\n");
            return;
        }

        try self.switcher.switchVersion(version.name, version.version, target);
    }

    // ------------------------
    // List installed Zig versions
    // ------------------------
    pub fn list(self: *Zig) !void {
        try self.lister.listVersions();
    }
};
