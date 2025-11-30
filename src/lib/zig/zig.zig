const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;

const ZigInstaller = @import("install.zig");
const ZigUninstaller = @import("uninstall.zig");
const ZigLister = @import("list.zig");
const ZigSwitcher = @import("switch.zig");

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
    printer: *Printer,

    installer: ZigInstaller.ZigInstaller,
    uninstaller: ZigUninstaller.ZigUninstaller,
    lister: ZigLister.ZigLister,
    switcher: ZigSwitcher.ZigSwitcher,

    // ------------------------
    // Initialize all submodules
    // ------------------------
    pub fn init(allocator: std.mem.Allocator, printer: *Printer) !Zig {
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
        const uri = try std.Uri.parse(Constants.Default.zig_download_index);
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &buffer });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();

        var reader = req.reader();
        const body = try reader.readAllAlloc(self.allocator, Constants.Default.mb * 50);
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
        try self.printer.append("Getting target version...\n", .{}, .{});
        var paths = try Constants.Paths.paths(self.allocator);
        defer paths.deinit();

        const version_data = self.fetchVersion(targetVersion) catch {
            try self.printer.append("Version not found...\n\n", .{}, .{});
            std.process.exit(0);
        };

        const obj = version_data.object;
        const url_value = obj.get(target) orelse {
            try self.printer.append("Target not found...\n\n", .{}, .{});
            return Version{ .name = "", .path = "", .tarball = "", .version = "" };
        };

        const tarball_value = url_value.object.get("tarball") orelse {
            try self.printer.append("Tarball not found...\n\n", .{}, .{});
            return Version{ .name = "", .path = "", .tarball = "", .version = "" };
        };
        const tarball = tarball_value.string;
        var resolved_version: []const u8 = targetVersion;
        if (obj.get("version")) |v| {
            resolved_version = v.string;
        }

        // Parse name from tarball URL
        const prefix = "https://ziglang.org/download/";
        const skip_length = prefix.len + targetVersion.len + 1;
        const name = if (builtin.os.tag == .windows) tarball[skip_length .. tarball.len - 4] else tarball[skip_length .. tarball.len - 7];

        const path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/d/{s}/{s}",
            .{ paths.zig_root, resolved_version, target },
        );

        return Version{
            .path = path,
            .name = name,
            .version = resolved_version,
            .tarball = tarball,
        };
    }

    // ------------------------
    // Install a Zig version
    // ------------------------
    pub fn install(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Installing version: {s}\nWith target: {s}\n\n", .{ targetVersion, target }, .{});
        const version = try self.getVersion(targetVersion, target);
        if (version.path.len == 0) return;

        if (Fs.existsDir(version.path)) {
            try self.printer.append("Zig version already installed.\n", .{}, .{});
            try self.printer.append("Use 'zeP zig switch x.x.x' to update.\n\n", .{}, .{});
            return;
        }

        try self.installer.install(version.name, version.tarball, version.version, target);
    }

    // ------------------------
    // Uninstall a Zig version
    // ------------------------
    pub fn uninstall(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Uninstalling version: {s}\nWith target: {s}\n\n", .{ targetVersion, target }, .{});
        const version = try self.getVersion(targetVersion, target);
        if (!Fs.existsDir(version.path)) {
            try self.printer.append("Zig version is not installed.\n\n", .{}, .{});
            return;
        }

        try self.uninstaller.uninstall(version.path);
    }

    // ------------------------
    // Switch active Zig version
    // ------------------------
    pub fn switchVersion(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        try self.printer.append("Switching version: {s}\nWith target: {s}\n\n", .{ targetVersion, target }, .{});
        const version = try self.getVersion(targetVersion, target);
        if (!Fs.existsDir(version.path)) {
            try self.printer.append("Zig version not installed.\n\n", .{}, .{});
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
