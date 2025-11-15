const std = @import("std");

const Constants = @import("constants");
const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;

pub const Clearer = struct {
    pub fn init() Clearer {
        return Clearer{};
    }

    fn clearCache(self: *Clearer) !void {
        _ = self;
        if (!try UtilsFs.checkDirExists(Constants.ROOT_ZEP_ZEPPED_FOLDER)) return;
        try std.fs.cwd().deleteTree(Constants.ROOT_ZEP_ZEPPED_FOLDER);
        return;
    }

    fn clearFingerprint(self: *Clearer) !void {
        _ = self;
        if (!try UtilsFs.checkFileExists(Constants.ROOT_ZEP_FINGERPRINTS_FILE)) return;
        try std.fs.cwd().deleteFile(Constants.ROOT_ZEP_FINGERPRINTS_FILE);
        return;
    }

    pub fn clear(self: *Clearer, mode: u8) !void {
        switch (mode) {
            0 => { // clear cache
                try self.clearCache();
            },
            1 => { // clear fingerprint
                try self.clearFingerprint();
            },
            else => {
                @panic("Invalid Mode");
            },
        }
    }
};
