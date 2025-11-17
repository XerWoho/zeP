const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;

pub const Clearer = struct {
    pub fn init() Clearer {
        return Clearer{};
    }

    fn clearCache(_: *Clearer) !void {
        if (try UtilsFs.checkDirExists(Constants.ROOT_ZEP_ZEPPED_FOLDER)) {
            try std.fs.cwd().deleteTree(Constants.ROOT_ZEP_ZEPPED_FOLDER);
        }
    }

    fn clearFingerprint(_: *Clearer) !void {
        if (try UtilsFs.checkFileExists(Constants.ROOT_ZEP_FINGERPRINTS_FILE)) {
            try std.fs.cwd().deleteFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE);
        }
    }

    pub fn clear(self: *Clearer, mode: u8) !void {
        switch (mode) {
            0 => try self.clearCache(),
            1 => try self.clearFingerprint(),
            else => return error.InvalidMode,
        }
    }
};
