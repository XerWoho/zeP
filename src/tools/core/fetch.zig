const std = @import("std");

const Logger = @import("logger");
const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;

const Json = @import("json.zig").Json;

/// writing into files.
pub const Fetch = struct {
    allocator: std.mem.Allocator,
    json: Json,
    paths: Constants.Paths.Paths,

    pub fn init(
        allocator: std.mem.Allocator,
        json: Json,
        paths: Constants.Paths.Paths,
    ) !Fetch {
        const logger = Logger.get();
        try logger.info("Fetch: init", @src());
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
            "http://localhost:5000/api/get/project?name={s}",
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

    pub fn fetchPackage(self: *Fetch, package_name: []const u8) !std.json.Parsed(Structs.Packages.PackageStruct) {
        const logger = Logger.get();
        try logger.infof("getPackage: fetching package {s}", .{package_name}, @src());

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        blk: {
            const fetched = self.fetchProject(package_name) catch {
                break :blk;
            };

            const releases = fetched.releases;
            var parsed_releases = try std.ArrayList(Structs.Packages.PackageVersions).initCapacity(
                self.allocator,
                releases.value.len,
            );
            for (releases.value) |r| {
                const pr = Structs.Packages.PackageVersions{
                    .root_file = r.RootFile,
                    .sha256sum = r.Hash,
                    .url = r.Url,
                    .version = r.Release,
                    .zig_version = r.ZigVersion,
                };
                try parsed_releases.append(self.allocator, pr);
            }

            const package = Structs.Packages.PackageStruct{
                .author = fetched.project.value.UserID,
                .name = fetched.project.value.Name,
                .docs = fetched.project.value.Docs,
                .versions = parsed_releases.items,
            };
            const s = try std.json.Stringify.valueAlloc(self.allocator, package, .{});
            const parsed = try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.allocator, s, .{});
            return parsed;
        }

        blk: {
            var buf: [128]u8 = undefined;
            const url = try std.fmt.bufPrint(
                &buf,
                "https://zep.run/packages/{s}.json",
                .{package_name},
            );
            const uri = try std.Uri.parse(url);

            var body = std.Io.Writer.Allocating.init(self.allocator);
            const fetched = try client.fetch(std.http.Client.FetchOptions{
                .location = .{ .uri = uri },
                .method = .GET,
                .response_writer = &body.writer,
            });
            if (fetched.status == .not_found) break :blk;
            const data = body.written();
            const parsed = try std.json.parseFromSlice(Structs.Packages.PackageStruct, self.allocator, data, .{});
            try logger.infof("parsePackage: successfully fetched and parsed {s} from URL", .{url}, @src());
            return parsed;
        }

        try logger.warnf("getPackage: package not found online {s}", .{package_name}, @src());

        var local_path_buf: [128]u8 = undefined;
        const local_path = try std.fmt.bufPrint(
            &local_path_buf,
            "{s}/{s}.json",
            .{ self.paths.custom, package_name },
        );
        if (!Fs.existsFile(local_path)) {
            try logger.warnf("getPackage: package not found locally {s}", .{local_path}, @src());
            return error.PackageNotFound;
        }

        const parsed = try self.json.parseJsonFromFile(Structs.Packages.PackageStruct, local_path, Constants.Default.mb * 10);
        try logger.infof("getPackage: loaded package from local file {s}", .{local_path}, @src());
        return parsed;
    }
};
