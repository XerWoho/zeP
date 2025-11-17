const std = @import("std");
pub const ZigManifest = struct { name: []const u8, path: []const u8 };

pub const PkgManifest = struct { name: []const u8, paths: [][]const u8 };

pub const PkgsManifest = struct { packages: []PkgManifest };

pub const BuildPackageJsonStruct = struct {
    entry: []const u8 = "src/main.zig",
    target: []const u8 = "",
};

pub const PackageJsonStruct = struct {
    author: []const u8 = "",
    tags: [][]const u8 = &[_][]const u8{},
    repo: []const u8 = "",
    name: []const u8 = "",
    description: []const u8 = "",
    version: []const u8 = "0.0.1",
    license: []const u8 = "",
    packages: [][]const u8 = &[_][]const u8{},
    devPackages: [][]const u8 = &[_][]const u8{},
    build: BuildPackageJsonStruct,
};

pub const PackageLockStruct = struct {
    schema: u8 = 1,
    root: PackageJsonStruct,
    packages: []LockPackageStruct = &[_]LockPackageStruct{},
};

pub const LockDepRef = struct {
    name: []const u8,
    version: []const u8,
};

pub const LockPackageStruct = struct {
    name: []const u8,
    author: []const u8,
    fingerprint: []const u8,
    source: []const u8,
};

pub const PackageStruct = struct {
    author: []const u8,
    tags: [][]const u8,
    git: []const u8,
    root_file: []const u8,
    description: []const u8,
    license: []const u8,
    updated_at: []const u8,
    homepage: ?[]const u8,
};

pub const ZepManifest = struct {
    version: []const u8,
    path: []const u8,
};
