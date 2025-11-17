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

    fn createFolders(_: *Init) !void {
        const cwd = std.fs.cwd();
        _ = cwd.makeDir(Constants.ZEP_FOLDER) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn createFiles(self: *Init) !void {
        const cwd = std.fs.cwd();
        const pkg = Structs.PackageJsonStruct{
            .build = Structs.BuildPackageJsonStruct{},
        };
        const lock = Structs.PackageLockStruct{
            .root = Structs.PackageJsonStruct{
                .build = Structs.BuildPackageJsonStruct{},
            },
        };

        if (!try UtilsFs.checkFileExists(Constants.ZEP_PACKAGE_FILE)) {
            const pkgString = try std.json.stringifyAlloc(self.allocator, pkg, .{ .whitespace = .indent_2 });
            _ = cwd.createFile(Constants.ZEP_PACKAGE_FILE, .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const pFile = try cwd.openFile(Constants.ZEP_PACKAGE_FILE, .{ .mode = .read_write });
            _ = try pFile.write(pkgString);
        }

        if (!try UtilsFs.checkFileExists(Constants.ZEP_LOCK_PACKAGE_FILE)) {
            const lockString = try std.json.stringifyAlloc(self.allocator, lock, .{ .whitespace = .indent_2 });
            _ = cwd.createFile(Constants.ZEP_LOCK_PACKAGE_FILE, .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const lFile = try cwd.openFile(Constants.ZEP_LOCK_PACKAGE_FILE, .{ .mode = .read_write });
            _ = try lFile.write(lockString);
        }
    }
};
