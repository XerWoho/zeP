const std = @import("std");
const builtin = @import("builtin");

// ------------------------
// Zig Download & Defaults
// ------------------------
pub const ZIG_V_JSON = "https://ziglang.org/download/index.json";
pub const DEFAULT_TARGET_WINDOWS = "x86_64-windows";
pub const DEFAULT_TARGET_LINUX = "x86_64-linux";

// ------------------------
// Helper Functions
// ------------------------
/// Returns base directory depending on OS
fn getBaseDir() []const u8 {
    const os = builtin.os.tag;
    if (os == .windows) {
        return "C:/Users/Public/AppData/Local";
    } else {
        return "/lib";
    }
}

// ------------------------
// Root ZeP Folders
// ------------------------
pub const ROOT_ZEP_FOLDER = getBaseDir() ++ "/zeP";
pub const ROOT_ZEP_PREBUILT_FOLDER = ROOT_ZEP_FOLDER ++ "/prebuilt";

// pub const ROOT_ZEP_PACKAGES = ROOT_ZEP_FOLDER ++ "/ava";

pub const ROOT_ZEP_CUSTOM_PACKAGES = ROOT_ZEP_FOLDER ++ "/customPackages";

pub const ROOT_ZEP_PKG_FOLDER = ROOT_ZEP_FOLDER ++ "/pkg";
pub const ROOT_ZEP_PKG_MANIFEST = ROOT_ZEP_PKG_FOLDER ++ "/manifest.json";

pub const ROOT_ZEP_ZIG_FOLDER = ROOT_ZEP_FOLDER ++ "/zig";
pub const ROOT_ZEP_ZIG_MANIFEST = ROOT_ZEP_ZIG_FOLDER ++ "/manifest.json";

// The folder where the current zep version
// is stored
pub const ROOT_ZEP_ZEP_FOLDER = ROOT_ZEP_FOLDER ++ "/zep";
pub const ROOT_ZEP_ZEP_MANIFEST = ROOT_ZEP_ZEP_FOLDER ++ "/manifest.json";

// ------------------------
// Cache & Metadata
// ------------------------
pub const ROOT_ZEP_CACHE_FOLDER = ROOT_ZEP_FOLDER ++ "/cache";
pub const ROOT_ZEP_ZEPPED_FOLDER = ROOT_ZEP_CACHE_FOLDER ++ "/zepped";
pub const ROOT_ZEP_FINGERPRINTS_FILE = ROOT_ZEP_CACHE_FOLDER ++ "/fingerprints.txt";

// ------------------------
// Local Zep Files / Folders
// ------------------------
pub const ZEP_FOLDER = ".zep";
pub const ZEP_INJECTOR = ZEP_FOLDER ++ "/inject.zig";

// ------------------------
// Package Files
// ------------------------
pub const ZEP_PACKAGE_FILE = "zep.json";
pub const ZEP_LOCK_PACKAGE_FILE = "zep.lock";

// ------------------------
// Filtering Rules
// ------------------------
pub const FILTER_PACKAGE_FOLDERS = [9][]const u8{
    ".git/",
    ".github/",
    ".vscode/",
    ".zig-cache/",
    "example/",
    "examples/",
    "test/",
    "tests/",
    "testdata/",
};

pub const FILTER_PACKAGE_FILES = [6][]const u8{
    ".editorconfig",
    ".gitignore",
    ".gitattributes",
    "LICENSE",
    "readme.md",
    "todo.md",
};
