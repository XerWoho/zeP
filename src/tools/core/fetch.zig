const std = @import("std");

pub const Fetch = @This();

const Constants = @import("constants");
const Locales = @import("locales");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("json.zig");
const Manifest = @import("manifest.zig");
const Hash = @import("hash.zig");

/// writing into files.
allocator: std.mem.Allocator,
paths: Constants.Paths.Paths,
manifest: Manifest,

client: std.http.Client,

pub fn init(
    allocator: std.mem.Allocator,
    paths: Constants.Paths.Paths,
    manifest: Manifest,
) Fetch {
    const client = std.http.Client{ .allocator = allocator };
    return Fetch{
        .allocator = allocator,
        .paths = paths,
        .manifest = manifest,
        .client = client,
    };
}

pub fn deinit(self: *Fetch) !void {
    self.client.deinit();
}

pub fn fetch(
    self: *Fetch,
    url: []const u8,
    options: Structs.Fetch.FetchOptions,
) !std.json.Parsed(std.json.Value) {
    var body = std.Io.Writer.Allocating.init(self.allocator);
    defer body.deinit();
    const res = try self.client.fetch(.{
        .location = .{ .url = url },
        .method = options.method,
        .payload = options.payload,
        .extra_headers = options.headers,
        .response_writer = &body.writer,
    });

    if (res.status == .not_found) {
        return error.NotFound;
    }
    const data = body.written();
    return std.json.parseFromSlice(
        std.json.Value,
        self.allocator,
        data,
        .{
            .allocate = .alloc_always,
        },
    );
}

pub fn fetchJson(
    self: *Fetch,
    url: []const u8,
    T: type,
) !std.json.Parsed(T) {
    var body = std.Io.Writer.Allocating.init(self.allocator);
    defer body.deinit();
    const res = try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
    });

    if (res.status == .not_found) {
        return error.NotFound;
    }
    const data = body.written();
    return std.json.parseFromSlice(
        T,
        self.allocator,
        data,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
}

pub fn fetchRaw(
    self: *Fetch,
    url: []const u8,
) ![]const u8 {
    var body = std.Io.Writer.Allocating.init(self.allocator);
    defer body.deinit();
    const res = try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
    });

    if (res.status == .not_found) {
        return error.NotFound;
    }

    const data = try self.allocator.dupe(u8, body.written());
    return data;
}

pub fn fetchWrite(
    self: *Fetch,
    url: []const u8,
    path: []const u8,
) !void {
    var file = try Fs.openOrCreateFile(path);
    defer file.close();

    var writer_buf: [Constants.Default.kb]u8 = undefined;
    var writer = file.writer(&writer_buf);
    const fetched = try self.client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &writer.interface,
    });
    _ = try writer.interface.flush();

    if (fetched.status == .not_found) return error.NotFound;
}

pub fn fetchPackage(self: *Fetch, name: []const u8) !Structs.Fetch.Package {
    const url = try std.fmt.allocPrint(
        self.allocator,
        Constants.Default.zep_url ++ "/api/v1/package?name={s}",
        .{name},
    );
    defer self.allocator.free(url);

    const get = try self.fetch(
        url,
        .{
            .method = .GET,
        },
    );
    defer get.deinit();
    const get_object = get.value.object;
    const success = get_object.get("success") orelse return error.FetchFailed;
    if (!success.bool) {
        return error.FetchFailed;
    }
    const object_package = get_object.get("package") orelse return error.FetchFailed;
    var object = object_package.object;
    defer object.deinit();

    const package_id = object.get("id") orelse return error.FetchFailed;
    const package_user_id = object.get("userId") orelse return error.FetchFailed;
    const package_name = object.get("name") orelse return error.FetchFailed;
    const package_description = object.get("description") orelse return error.FetchFailed;
    const package_docs = object.get("docs") orelse return error.FetchFailed;
    const package_tags = object.get("tags") orelse return error.FetchFailed;
    const package_created_at = object.get("created_at") orelse return error.FetchFailed;
    const package = Structs.Fetch.Package{
        .ID = package_id.string,
        .UserID = package_user_id.string,
        .Name = package_name.string,
        .Description = package_description.string,
        .Docs = package_docs.string,
        .Tags = package_tags.string,
        .CreatedAt = package_created_at.string,
    };

    return package;
}

pub fn fetchPackages(self: *Fetch) !std.ArrayList(Structs.Fetch.Package) {
    var manifest = try self.manifest.readManifest(
        Structs.Manifests.Auth,
        self.paths.auth_manifest,
    );
    defer manifest.deinit();
    if (manifest.value.token.len == 0) {
        return error.NotAuthed;
    }

    const url = Constants.Default.zep_url ++ "/api/v1/packages";
    const get = try self.fetch(
        url,
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = try manifest.value.bearer(),
                },
            },
        },
    );
    defer get.deinit();
    const object = get.value.object;
    const success = object.get("success") orelse return error.FetchFailed;
    if (!success.bool) {
        return error.FetchFailed;
    }
    const object_packages = object.get("packages") orelse return error.FetchFailed;
    const array = object_packages.array;
    defer array.deinit();

    var packages = try std.ArrayList(Structs.Fetch.Package).initCapacity(
        self.allocator,
        array.items.len,
    );
    for (array.items) |package_value| {
        const package = package_value.object;
        const package_id = package.get("id") orelse return error.FetchFailed;
        const package_user_id = package.get("userId") orelse return error.FetchFailed;
        const package_name = package.get("name") orelse return error.FetchFailed;
        const package_description = package.get("description") orelse return error.FetchFailed;
        const package_docs = package.get("docs") orelse return error.FetchFailed;
        const package_tags = package.get("tags") orelse return error.FetchFailed;
        const package_created_at = package.get("created_at") orelse return error.FetchFailed;
        const package_struct = Structs.Fetch.Package{
            .ID = package_id.string,
            .UserID = package_user_id.string,
            .Name = package_name.string,
            .Description = package_description.string,
            .Docs = package_docs.string,
            .Tags = package_tags.string,
            .CreatedAt = package_created_at.string,
        };

        try packages.append(self.allocator, package_struct);
    }

    return packages;
}

pub fn fetchReleases(self: *Fetch, name: []const u8) !std.ArrayList(Structs.Fetch.Release) {
    var auth = try self.manifest.readManifest(
        Structs.Manifests.Auth,
        self.paths.auth_manifest,
    );
    defer auth.deinit();
    if (auth.value.token.len == 0) {
        return error.NotAuthed;
    }

    const url = try std.fmt.allocPrint(
        self.allocator,
        Constants.Default.zep_url ++ "/api/v1/releases?package_name={s}",
        .{name},
    );
    defer self.allocator.free(url);
    const get = try self.fetch(
        url,
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = try auth.value.bearer(),
                },
            },
        },
    );
    defer get.deinit();
    const object = get.value.object;
    const success = object.get("success") orelse return error.FetchFailed;
    if (!success.bool) {
        return error.FetchFailed;
    }
    const object_releases = object.get("releases") orelse return error.FetchFailed;
    const array = object_releases.array;
    defer array.deinit();

    var releases = try std.ArrayList(Structs.Fetch.Release).initCapacity(
        self.allocator,
        array.items.len,
    );
    for (array.items) |release_value| {
        const release = release_value.object;
        const release_id = release.get("id") orelse return error.FetchFailed;
        const release_user_id = release.get("userId") orelse return error.FetchFailed;
        const release_package_id = release.get("packageId") orelse return error.FetchFailed;
        const release_url = release.get("url") orelse return error.FetchFailed;
        const release_release = release.get("release") orelse return error.FetchFailed;
        const release_zig_version = release.get("zig_version") orelse return error.FetchFailed;
        const release_hash = release.get("hash") orelse return error.FetchFailed;
        const release_root_file = release.get("root_file") orelse return error.FetchFailed;
        const release_created_at = release.get("created_at") orelse return error.FetchFailed;
        const release_updated_at = release.get("updated_at") orelse return error.FetchFailed;
        const release_struct = Structs.Fetch.Release{
            .ID = release_id.string,
            .UserID = release_user_id.string,
            .PackageID = release_package_id.string,
            .Url = release_url.string,
            .Release = release_release.string,
            .ZigVersion = release_zig_version.string,
            .Hash = release_hash.string,
            .RootFile = release_root_file.string,
            .CreatedAt = release_created_at.string,
            .UpdatedAt = release_updated_at.string,
        };

        try releases.append(self.allocator, release_struct);
    }

    return releases;
}
