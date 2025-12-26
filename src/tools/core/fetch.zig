const std = @import("std");

pub const Fetch = @This();

const Logger = @import("logger");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("json.zig");

/// writing into files.
allocator: std.mem.Allocator,
json: Json,
paths: Constants.Paths.Paths,
install_unverified_packages: bool = false,

pub fn init(
    allocator: std.mem.Allocator,
    json: Json,
    paths: Constants.Paths.Paths,
) Fetch {
    return Fetch{
        .allocator = allocator,
        .paths = paths,
        .json = json,
    };
}

pub fn fetch(
    self: *Fetch,
    url: []const u8,
    client: *std.http.Client,
    options: Structs.Fetch.FetchOptions,
) !std.json.Parsed(std.json.Value) {
    const uri = try std.Uri.parse(url);

    var body = std.Io.Writer.Allocating.init(self.allocator);
    const res = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = options.method,
        .payload = options.payload,
        .extra_headers = options.headers,
        .response_writer = &body.writer,
    });

    if (res.status == .not_found) {
        return error.NotFound;
    }

    return std.json.parseFromSlice(
        std.json.Value,
        self.allocator,
        body.written(),
        .{},
    );
}

pub fn fetchProject(self: *Fetch, name: []const u8) !struct {
    project: std.json.Parsed(Structs.Fetch.ProjectStruct),
    releases: std.json.Parsed([]Structs.Fetch.ReleaseStruct),
} {
    const url = try std.fmt.allocPrint(
        self.allocator,
        Constants.Default.zep_url ++ "/api/get/project?name={s}",
        .{name},
    );
    defer self.allocator.free(url);

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();
    const get_project_response = try self.fetch(
        url,
        &client,
        .{
            .method = .GET,
        },
    );
    defer get_project_response.deinit();
    const get_project_object = get_project_response.value.object;
    const is_get_project_successful = get_project_object.get("success") orelse return error.InvalidFetch;
    if (!is_get_project_successful.bool) {
        return error.InvalidFetch;
    }
    const project = get_project_object.get("project") orelse return error.InvalidFetch;
    const project_decoded = try self.allocator.alloc(
        u8,
        try std.base64.standard.Decoder.calcSizeForSlice(project.string),
    );
    try std.base64.standard.Decoder.decode(project_decoded, project.string);
    const project_parsed: std.json.Parsed(Structs.Fetch.ProjectStruct) = try std.json.parseFromSlice(
        Structs.Fetch.ProjectStruct,
        self.allocator,
        project_decoded,
        .{},
    );

    const releases = get_project_object.get("releases") orelse return error.InvalidFetch;
    const release_decoded = try self.allocator.alloc(
        u8,
        try std.base64.standard.Decoder.calcSizeForSlice(releases.string),
    );
    try std.base64.standard.Decoder.decode(release_decoded, releases.string);
    const release_parsed: std.json.Parsed([]Structs.Fetch.ReleaseStruct) = try std.json.parseFromSlice(
        []Structs.Fetch.ReleaseStruct,
        self.allocator,
        release_decoded,
        .{},
    );

    return .{
        .project = project_parsed,
        .releases = release_parsed,
    };
}

fn fetchFromProject(
    self: *Fetch,
    package_name: []const u8,
) !std.json.Parsed(Structs.Packages.PackageStruct) {
    const fetched = try self.fetchProject(package_name);

    var versions = try std.ArrayList(Structs.Packages.PackageVersions)
        .initCapacity(self.allocator, fetched.releases.value.len);

    for (fetched.releases.value) |r| {
        try versions.append(self.allocator, .{
            .root_file = r.RootFile,
            .sha256sum = r.Hash,
            .url = r.Url,
            .version = r.Release,
            .zig_version = r.ZigVersion,
        });
    }

    const arena = try self.allocator.create(std.heap.ArenaAllocator);
    return std.json.Parsed(Structs.Packages.PackageStruct){
        .arena = arena, // or your arena
        .value = .{
            .author = fetched.project.value.UserID,
            .name = fetched.project.value.Name,
            .docs = fetched.project.value.Docs,
            .versions = versions.items,
        },
    };
}

fn fetchFromUrl(
    self: *Fetch,
    package_name: []const u8,
) !std.json.Parsed(Structs.Packages.PackageStruct) {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        "https://zep.run/packages/{s}.json",
        .{package_name},
    );

    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(self.allocator);
    const res = try client.fetch(.{
        .location = .{ .uri = try std.Uri.parse(url) },
        .method = .GET,
        .response_writer = &body.writer,
    });

    if (res.status == .not_found) return error.PackageNotFound;

    return std.json.parseFromSlice(
        Structs.Packages.PackageStruct,
        self.allocator,
        body.written(),
        .{},
    );
}

fn loadFromLocal(
    self: *Fetch,
    package_name: []const u8,
) !std.json.Parsed(Structs.Packages.PackageStruct) {
    var buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &buf,
        "{s}/{s}.json",
        .{ self.paths.custom, package_name },
    );

    if (!Fs.existsFile(path)) return error.PackageNotFound;

    return self.json.parseJsonFromFile(
        Structs.Packages.PackageStruct,
        path,
        Constants.Default.mb * 10,
    );
}

pub fn fetchPackage(
    self: *Fetch,
    package_name: []const u8,
) !std.json.Parsed(Structs.Packages.PackageStruct) {
    if (self.install_unverified_packages) {
        if (self.fetchFromProject(package_name)) |pkg| {
            return pkg;
        } else |_| {}
    }

    if (self.fetchFromUrl(package_name)) |pkg| {
        return pkg;
    } else |_| {}

    if (self.loadFromLocal(package_name)) |pkg| {
        return pkg;
    } else |_| {}

    return error.PackageNotFound;
}
