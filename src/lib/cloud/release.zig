const std = @import("std");

pub const Release = @This();

const Constants = @import("constants");
const Structs = @import("structs");

const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Compressor = @import("core").Compressor;

const Projects = @import("project.zig");

const FetchOptions = struct {
    payload: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
    method: std.http.Method = .POST,
};

const boundary =
    "----eb542ed298bc07fa2f58d09191f02dbbffbaa477";

const Context = @import("context");

/// Handles Projects
ctx: *Context,

pub fn init(
    ctx: *Context,
) Release {
    return .{
        .ctx = ctx,
    };
}

pub fn delete(self: *Release) !void {
    var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
    defer auth_manifest.deinit();

    var initted_project = Projects.init(self.ctx);

    const projects = try initted_project.getProjects();
    try self.ctx.printer.append("Available projects:\n", .{}, .{});
    for (projects, 0..) |r, i| {
        try self.ctx.printer.append(" [{d}] - {s}\n", .{ i, r.Name }, .{});
    }
    try self.ctx.printer.append("\n", .{}, .{});

    const project_index_str = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "TARGET >> ",
        .{ .required = true },
    );
    try self.ctx.printer.append("\n", .{}, .{});

    const project_index = try std.fmt.parseInt(
        usize,
        project_index_str,
        10,
    );

    if (project_index >= projects.len)
        return error.InvalidSelection;

    const project_target = projects[project_index];
    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();

    const fetched = try initted_project.getProject(project_target.Name);
    const fetched_project = fetched orelse return error.NotFound;
    const project = fetched_project.project;
    defer project.deinit();

    const releases = fetched_project.releases;
    defer releases.deinit();

    try self.ctx.printer.append("Available releases:\n", .{}, .{});
    for (releases.value, 0..) |v, i| {
        try self.ctx.printer.append(
            "  [{d}] - {s} {s}\n",
            .{ i, project_target.Name, v.Release },
            .{ .color = .bright_blue },
        );
    }
    try self.ctx.printer.append("\n", .{}, .{});
    const release_index_str = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "TARGET >> ",
        .{ .required = true },
    );
    try self.ctx.printer.append("\n", .{}, .{});

    const release_index = try std.fmt.parseInt(
        usize,
        release_index_str,
        10,
    );

    if (release_index >= releases.value.len)
        return error.InvalidSelection;

    const release_target = releases.value[release_index];

    const DeleteReleasePayload = struct {
        id: []const u8,
        project_id: []const u8,
    };
    const delete_release_payload = DeleteReleasePayload{
        .id = release_target.ID,
        .project_id = project_target.ID,
    };

    const delete_release_response = try self.ctx.fetcher.fetch(
        "http://localhost:5000/api/delete/release",
        &client,
        .{
            .method = .DELETE,
            .headers = &.{
                std.http.Header{
                    .name = "Bearer",
                    .value = auth_manifest.value.token,
                },
            },
            .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, delete_release_payload, .{}),
        },
    );
    defer delete_release_response.deinit();
    const delete_release_object = delete_release_response.value.object;
    const is_delete_release_successful = delete_release_object.get("success") orelse return;
    if (!is_delete_release_successful.bool) {
        return;
    }
}

pub fn list(self: *Release) !void {
    var initted_project = Projects.init(self.ctx);

    const projects = try initted_project.getProjects();
    try self.ctx.printer.append("Available projects:\n", .{}, .{});
    for (projects, 0..) |r, i| {
        try self.ctx.printer.append(" [{d}] - {s}\n", .{ i, r.Name }, .{});
    }
    try self.ctx.printer.append("\n", .{}, .{});

    const project_index_str = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "TARGET >> ",
        .{ .required = true },
    );
    try self.ctx.printer.append("\n", .{}, .{});

    const project_index = try std.fmt.parseInt(
        usize,
        project_index_str,
        10,
    );

    if (project_index >= projects.len)
        return error.InvalidSelection;

    const project_target = projects[project_index];
    const fetch = try initted_project.getProject(project_target.Name);
    const fetched_project = fetch orelse return error.NotFound;
    const project = fetched_project.project;
    defer project.deinit();

    const releases = fetched_project.releases;
    defer releases.deinit();

    try self.ctx.printer.append("Available releases:\n", .{}, .{});
    for (releases.value, 0..) |v, i| {
        try self.ctx.printer.append(
            "  [{d}] - {s} {s}\n",
            .{ i, project_target.Name, v.Release },
            .{ .color = .bright_blue },
        );
    }
    try self.ctx.printer.append("\n", .{}, .{});
}

const TEMPORARY_DIRECTORY_PATH = ".zep/.ZEPtmp";
const TEMPORARY_FILE = "pkg.tar.zstd";
fn compressProject(
    self: *Release,
) ![]const u8 {
    const output = TEMPORARY_DIRECTORY_PATH ++ "/" ++ TEMPORARY_FILE;
    try self.ctx.compressor.compress("", output);

    try self.ctx.printer.append(
        "Compressed!\n\n",
        .{},
        .{ .color = .green },
    );

    return output;
}

fn formField(
    self: *Release,
    name: []const u8,
    value: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        self.ctx.allocator,
        "--{s}\r\n" ++
            "Content-Disposition: form-data; name=\"{s}\"\r\n\r\n" ++
            "{s}\r\n",
        .{ boundary, name, value },
    );
}

fn formFileHeader(
    self: *Release,
    filename: []const u8,
    mime: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        self.ctx.allocator,
        "--{s}\r\n" ++
            "Content-Disposition: form-data; name=\"package\"; filename=\"{s}\"\r\n" ++
            "Content-Type: {s}\r\n\r\n",
        .{ boundary, filename, mime },
    );
}

pub fn create(self: *Release) !void {
    try self.ctx.printer.append("--- CREATING RELEASE MODE ---\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    var auth = try self.ctx.manifest.readManifest(
        Structs.Manifests.AuthManifest,
        self.ctx.paths.auth_manifest,
    );
    defer auth.deinit();

    var initted_project = Projects.init(self.ctx);

    const projects = try initted_project.getProjects();
    defer self.ctx.allocator.free(projects);

    if (projects.len == 0) {
        try self.ctx.printer.append(
            "No project available!\nCreate project first!\n\n",
            .{},
            .{ .color = .red },
        );
        return;
    }

    try self.ctx.printer.append(
        "Select Project target:\n\n",
        .{},
        .{ .color = .blue, .weight = .bold },
    );

    for (projects, 0..) |r, i| {
        try self.ctx.printer.append(
            " - [{d}] {s}\n",
            .{ i, r.Name },
            .{},
        );
    }
    try self.ctx.printer.append("\n", .{}, .{});

    const index_str = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "TARGET >> ",
        .{ .required = true },
    );
    try self.ctx.printer.append("\n", .{}, .{});

    const index = try std.fmt.parseInt(
        usize,
        index_str,
        10,
    );

    if (index >= projects.len)
        return error.InvalidSelection;

    const target = projects[index];

    const p_release = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Release*: ",
        .{ .required = true },
    );

    const zig_version = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Zig Version*: ",
        .{ .required = true },
    );

    const root_file = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Root File*: ",
        .{ .required = true },
    );
    try self.ctx.printer.append("\n", .{}, .{});

    const archive = try self.compressProject();

    const file = try Fs.openFile(archive);
    defer file.close();

    const stat = try file.stat();
    const data = try self.ctx.allocator.alloc(u8, stat.size);
    defer self.ctx.allocator.free(data);
    _ = try file.readAll(data);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(data);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    const hash_hex =
        try std.fmt.allocPrint(self.ctx.allocator, "{x}", .{digest});

    const output = TEMPORARY_DIRECTORY_PATH ++ "/" ++ TEMPORARY_FILE;
    const body = try std.mem.concat(
        self.ctx.allocator,
        u8,
        &.{
            try self.formFileHeader(output, "application/zstd"),
            data,
            "\r\n",
            try self.formField("project_id", target.ID),
            try self.formField("hash", hash_hex),
            try self.formField("release", p_release),
            try self.formField("zig_version", zig_version),
            try self.formField("root_file", root_file),
            try std.fmt.allocPrint(
                self.ctx.allocator,
                "--{s}--\r\n",
                .{boundary},
            ),
        },
    );

    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();

    const uri =
        try std.Uri.parse("http://localhost:5000/api/post/release");

    var req = try client.request(.POST, uri, .{});
    defer req.deinit();

    req.headers.content_type = .{
        .override = "multipart/form-data; boundary=" ++ boundary,
    };
    req.transfer_encoding = .{ .content_length = body.len };
    req.extra_headers = &.{
        .{ .name = "Bearer", .value = auth.value.token },
    };

    _ = try req.sendBodyComplete(body);

    var head_buf: [Constants.Default.kb]u8 = undefined;
    var head = try req.receiveHead(&head_buf);

    var read_buf: [Constants.Default.kb]u8 = undefined;
    var response_reader = head.reader(&read_buf);
    const response_buffer_len = response_reader.bufferedLen();
    const response_buffer = try self.ctx.allocator.alloc(u8, response_buffer_len);
    _ = try response_reader.readSliceAll(response_buffer);

    try self.ctx.printer.append(
        "Release {s} has been successfully projectd!\n",
        .{
            p_release,
        },
        .{ .color = .bright_green },
    );

    try self.ctx.printer.append(
        "Install project via\n $ zep install {s}@{s} --unverified\n\n",
        .{
            target.Name,
            p_release,
        },
        .{},
    );

    try Fs.deleteTreeIfExists(".zep/.pkg/");
}
