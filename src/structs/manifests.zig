const Constants = @import("constants");

pub const ArtifactManifest = struct {
    name: []const u8 = "",
    path: []const u8 = "",
};

pub const PackagePaths = struct {
    name: []const u8 = "",
    paths: [][]const u8 = &[_][]const u8{},
};

pub const PackagesManifest = struct {
    packages: []PackagePaths = &[_]PackagePaths{},
};

pub const InjectorManifest = struct {
    schema: u8 = 1,
    included_modules: [][]const u8 = &[_][]const u8{},
    excluded_modules: [][]const u8 = &[_][]const u8{},
};
