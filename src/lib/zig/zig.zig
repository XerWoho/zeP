const std = @import("std");

const MAX_SIZE = 1028 * 1028 * 50;

const ZigUninstaller = @import("uninstall.zig");
const ZigInstaller = @import("install.zig");
const ZigLister = @import("list.zig");
const ZigSwitcher = @import("switch.zig");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;
const UtilsPrinter = Utils.UtilsPrinter;

const Manifest = @import("lib/manifest.zig");

const Version = struct {
    path: []const u8,
    tarball: []const u8,
    name: []const u8,
    version: []const u8,
};

pub const Zig = struct {
    allocator: std.mem.Allocator,
    uninstaller: ZigUninstaller.ZigUninstaller,
    installer: ZigInstaller.ZigInstaller,
    lister: ZigLister.ZigLister,
    switcher: ZigSwitcher.ZigSwitcher,

    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, printer: *UtilsPrinter.Printer) !Zig {
        const uninstaller = try ZigUninstaller.ZigUninstaller.init(allocator, printer);
        const installer = try ZigInstaller.ZigInstaller.init(allocator, printer);
        const lister = try ZigLister.ZigLister.init(allocator, printer);
        const switcher = try ZigSwitcher.ZigSwitcher.init(allocator, printer);

        return Zig{
            .allocator = allocator,
            .printer = printer,
            .uninstaller = uninstaller,
            .installer = installer,
            .lister = lister,
            .switcher = switcher,
        };
    }

    pub fn deinit(self: *Zig) void {
        defer {
            self.installer.deinit();
            self.uninstaller.deinit();
            self.switcher.deinit();
            self.lister.deinit();
        }
    }

    fn fetchVersion(self: *Zig, targetVersion: []const u8) !std.json.Value {
        // Create a HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var buf: [4096]u8 = undefined;
        const uri = try std.Uri.parse(Constants.ZIG_V_JSON);
        var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();
        var rdr = req.reader();

        const body = try rdr.readAllAlloc(self.allocator, MAX_SIZE);
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});

        const root = parsed.value;
        const obj = root.object;

        if (std.mem.eql(u8, targetVersion, "latest") or targetVersion.len == 0) {
            const version = obj.get("master") orelse return error.NotFound;
            return version;
        }
        const version = obj.get(targetVersion) orelse return error.NotFound;
        return version;
    }

    pub fn getVersion(self: *Zig, targetVersion: []const u8, target: []const u8) !Version {
        try self.printer.append("Getting target version...\n");
        const version = self.fetchVersion(targetVersion) catch {
            try self.printer.append("Version not found...\n\n");
            std.process.exit(0);
        };
        const obj = version.object;
        const url = obj.get(target);
        if (url == null) {
            try self.printer.append("Not found...\n\n");
            return Version{
                .path = "",
                .name = "",
                .version = "",
                .tarball = "",
            };
        }

        try self.printer.append("Target Version found!\n\n");
        const objTarball = url.?.object.get("tarball");
        const tarball = objTarball.?.string;

        var v = targetVersion;
        if (obj.get("version")) |o| {
            v = o.string;
        }

        var skipLength: u16 = 0;
        const s = "https://ziglang.org/download/";
        skipLength = s.len;
        skipLength += @intCast(targetVersion.len + 1);
        const name = tarball[skipLength .. tarball.len - 4];
        const path = try std.fmt.allocPrint(self.allocator, "{s}/d/{s}/{s}", .{ Constants.ROOT_ZEP_ZIG_FOLDER, v, target });
        return Version{
            .path = path,
            .name = name,
            .version = v,
            .tarball = tarball,
        };
    }

    pub fn install(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        const installVersion = try std.fmt.allocPrint(self.allocator, "Installing version\n > {s}\n", .{targetVersion});
        try self.printer.append(installVersion);
        const withTarget = try std.fmt.allocPrint(self.allocator, "With target\n > {s}\n\n", .{target});
        try self.printer.append(withTarget);

        const version = try self.getVersion(targetVersion, target);
        if (try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version already installed...\n");
            try self.printer.append("Use 'zeP zig switch x.x.x' if the path is not up-to-date.\n\n");
            return;
        }

        try self.installer.install(version.name, version.tarball, version.version, target);
    }

    pub fn uninstall(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        const uninstallVersion = try std.fmt.allocPrint(self.allocator, "Uninstall version\n > {s}\n", .{targetVersion});
        try self.printer.append(uninstallVersion);
        const withTarget = try std.fmt.allocPrint(self.allocator, "With target\n > {s}\n\n", .{target});
        try self.printer.append(withTarget);

        const version = try self.getVersion(targetVersion, target);
        if (!try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version is not installed...\n\n");
            return;
        }
        try self.uninstaller.uninstall(version.path);
    }

    pub fn switchV(self: *Zig, targetVersion: []const u8, target: []const u8) !void {
        const switchVersion = try std.fmt.allocPrint(self.allocator, "Switch version\n > {s}\n", .{targetVersion});
        try self.printer.append(switchVersion);
        const withTarget = try std.fmt.allocPrint(self.allocator, "With target\n > {s}\n\n", .{target});
        try self.printer.append(withTarget);

        const version = try self.getVersion(targetVersion, target);
        if (!try UtilsFs.checkDirExists(version.path)) {
            try self.printer.append("Zig version not installed...\n\n");
            return;
        }
        try self.switcher.switchVersion(version.name, version.version, target);
    }

    pub fn list(self: *Zig) !void {
        try self.lister.listVersions();
    }
};
