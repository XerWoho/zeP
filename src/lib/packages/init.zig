const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");
const Utils = @import("utils");
const UtilsJson = Utils.UtilsJson;
const UtilsFs = Utils.UtilsFs;

pub const Init = struct {
    allocator: std.mem.Allocator,
    json: UtilsJson.Json,

    pub fn init(allocator: std.mem.Allocator) !Init {
        const json = try UtilsJson.Json.init(allocator);
        return Init{ .allocator = allocator, .json = json };
    }

    pub fn commitInit(self: *Init) !void {
        try self.createFolders();
        try self.createFiles();
    }

    fn initDefJson(self: *Init) !Structs.PackageJsonStruct {
        _ = self;
        const build = Structs.BuildPackageJsonStruct{};
        const json = Structs.PackageJsonStruct{
            .build = build,
        };
        return json;
    }

    fn initDefLock(self: *Init, pkgJson: Structs.PackageJsonStruct) !Structs.PackageLockStruct {
        _ = self;
        const lock = Structs.PackageLockStruct{
            .root = pkgJson,
        };
        return lock;
    }

    fn createFolders(self: *Init) !void {
        _ = self;
        _ = std.fs.cwd().makeDir(Constants.ZEP_FOLDER) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn createFiles(self: *Init) !void {
        var pkg = try self.initDefJson();
        var lock = try self.initDefLock(pkg);

        if (!try UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE)) {
            const pkgString = try self.json.stringifyPkgJson(&pkg);
            _ = std.fs.cwd().createFile(Constants.ZEP_PACKAGE_FILE, .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const pFile = try std.fs.cwd().openFile(Constants.ZEP_PACKAGE_FILE, std.fs.File.OpenFlags{ .mode = .read_write });
            _ = try pFile.write(pkgString);
        }

        if (!try UtilsFs.checkFileExists(Constants.ZEP_LOCK_PACKAGE_FILE)) {
            const lockString = try self.json.stringifyLockJson(&lock);
            _ = std.fs.cwd().createFile(Constants.ZEP_LOCK_PACKAGE_FILE, .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const lFile = try std.fs.cwd().openFile(Constants.ZEP_LOCK_PACKAGE_FILE, std.fs.File.OpenFlags{ .mode = .read_write });
            _ = try lFile.write(lockString);
        }
    }
};
