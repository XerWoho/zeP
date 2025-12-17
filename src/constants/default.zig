const std = @import("std");
const builtin = @import("builtin");

pub const zig_download_index = "https://ziglang.org/download/index.json";
pub const zep_download_index = "https://zep.run/download.json";
pub const kb = 1024;
pub const mb = kb * kb;
pub const version = "0.8";

pub const default_targets = struct {
    pub const windows = "x86_64-windows";
    pub const linux = "x86_64-linux";
};
