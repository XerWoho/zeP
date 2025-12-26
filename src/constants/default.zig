const std = @import("std");
const builtin = @import("builtin");

pub const zig_download_index = "https://ziglang.org/download/index.json";
pub const zep_url = "http://localhost:5000";
pub const zep_download_index = zep_url ++ "/download.json";
pub const kb = 1024;
pub const mb = kb * kb;
pub const version = "0.9.0";

pub const default_targets = struct {
    pub const windows = "x86_64-windows";
    pub const linux = "x86_64-linux";
    pub const macos = "x86_64-macos";
};

/// Resolve default target if no target specified
pub fn resolveDefaultTarget() []const u8 {
    return switch (builtin.target.os.tag) {
        .windows => default_targets.windows,
        .macos => default_targets.macos,
        else => default_targets.linux,
    };
}
