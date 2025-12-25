const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Compressor = @import("core").Compressor;

const Context = @import("context").Context;

/// Handles Projects
pub const Project = struct {
    ctx: *Context,

    pub fn init(ctx: *Context) Project {
        return .{
            .ctx = ctx,
        };
    }

    pub fn getProjects(self: *Project) ![]Structs.Fetch.ProjectStruct {
        var auth = try self.ctx.manifest.readManifest(
            Structs.Manifests.AuthManifest,
            self.ctx.paths.auth_manifest,
        );
        defer auth.deinit();

        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();

        const res = try self.ctx.fetcher.fetch(
            "http://localhost:5000/api/get/projects",
            &client,
            .{
                .method = .GET,
                .headers = &.{
                    .{ .name = "Bearer", .value = auth.value.token },
                },
            },
        );
        defer res.deinit();

        const encoded = res.value.object
            .get("projects") orelse return error.InvalidFetch;
        const decoded = try self.ctx.allocator.alloc(
            u8,
            try std.base64.standard.Decoder.calcSizeForSlice(encoded.string),
        );

        try std.base64.standard.Decoder.decode(decoded, encoded.string);
        const parsed: std.json.Parsed([]Structs.Fetch.ProjectStruct) = try std.json.parseFromSlice(
            []Structs.Fetch.ProjectStruct,
            self.ctx.allocator,
            decoded,
            .{},
        );
        defer parsed.deinit();
        const parsed_projects = parsed.value;
        const parsed_projects_duped = try self.ctx.allocator.dupe(Structs.Fetch.ProjectStruct, parsed_projects);
        return parsed_projects_duped;
    }

    pub fn getProject(self: *Project, name: []const u8) !struct {
        project: std.json.Parsed(Structs.Fetch.ProjectStruct),
        releases: std.json.Parsed([]Structs.Fetch.ReleaseStruct),
    } {
        const url = try std.fmt.allocPrint(
            self.ctx.allocator,
            "http://localhost:5000/api/get/project?name={s}",
            .{name},
        );
        defer self.ctx.allocator.free(url);

        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();
        const get_project_response = try self.ctx.fetcher.fetch(
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
        const project_decoded = try self.ctx.allocator.alloc(
            u8,
            try std.base64.standard.Decoder.calcSizeForSlice(project.string),
        );
        try std.base64.standard.Decoder.decode(project_decoded, project.string);
        const project_parsed: std.json.Parsed(Structs.Fetch.ProjectStruct) = try std.json.parseFromSlice(
            Structs.Fetch.ProjectStruct,
            self.ctx.allocator,
            project_decoded,
            .{},
        );

        const releases = get_project_object.get("releases") orelse return error.InvalidFetch;
        const release_decoded = try self.ctx.allocator.alloc(
            u8,
            try std.base64.standard.Decoder.calcSizeForSlice(releases.string),
        );
        try std.base64.standard.Decoder.decode(release_decoded, releases.string);
        const release_parsed: std.json.Parsed([]Structs.Fetch.ReleaseStruct) = try std.json.parseFromSlice(
            []Structs.Fetch.ReleaseStruct,
            self.ctx.allocator,
            release_decoded,
            .{},
        );

        return .{
            .project = project_parsed,
            .releases = release_parsed,
        };
    }

    pub fn delete(self: *Project) !void {
        var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
        defer auth_manifest.deinit();

        const projects = try self.getProjects();
        try self.ctx.printer.append("Available projects:\n", .{}, .{});
        for (projects, 0..) |p, i| {
            try self.ctx.printer.append(" [{d}] - {s}\n", .{ i, p.Name }, .{});
        }
        try self.ctx.printer.append("\n", .{}, .{});

        var stdin_buf: [128]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        const index_str = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
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
        const target_id = target.ID;

        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();

        const fetched_project = try self.getProject(target.Name);
        const project = fetched_project.project;
        defer project.deinit();

        const releases = fetched_project.releases;
        defer releases.deinit();
        if (releases.value.len != 0) {
            try self.ctx.printer.append(
                " ! Selected project has {d} release(s)\n\n",
                .{releases.value.len},
                .{
                    .color = .red,
                },
            );
            for (releases.value) |r| {
                try self.ctx.printer.append(
                    "  > {s} {s}\n    ({s})\n",
                    .{
                        project.value.Name,
                        r.Release,
                        r.Hash,
                    },
                    .{},
                );
            }
            try self.ctx.printer.append(
                "\nYou want to continue?\n\n",
                .{},
                .{},
            );
            const yes_delete_project = try Prompt.input(
                self.ctx.allocator,
                &self.ctx.printer,
                stdin,
                "(y/N) ",
                .{},
            );
            if (yes_delete_project.len == 0) return;
            if (!std.mem.startsWith(u8, yes_delete_project, "y") and
                !std.mem.startsWith(u8, yes_delete_project, "Y")) return;
        } else {
            try self.ctx.printer.append(
                "Deleting project...\n\n",
                .{},
                .{ .color = .red },
            );
        }

        const DeleteProjectPayload = struct {
            id: []const u8,
        };
        const delete_project_payload = DeleteProjectPayload{
            .id = target_id,
        };

        const delete_project_response = try self.ctx.fetcher.fetch(
            "http://localhost:5000/api/delete/project",
            &client,
            .{
                .method = .DELETE,
                .headers = &.{
                    std.http.Header{
                        .name = "Bearer",
                        .value = auth_manifest.value.token,
                    },
                },
                .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, delete_project_payload, .{}),
            },
        );
        defer delete_project_response.deinit();
        const delete_project_object = delete_project_response.value.object;
        const is_delete_project_successful = delete_project_object.get("success") orelse return;
        if (!is_delete_project_successful.bool) {
            return;
        }
    }

    pub fn list(self: *Project) !void {
        const projects = try self.getProjects();
        try self.ctx.printer.append("Available projects:\n", .{}, .{});
        for (projects) |r| {
            try self.ctx.printer.append(" - {s}\n  > {s}\n", .{ r.Name, r.ID }, .{});
        }
        try self.ctx.printer.append("\n", .{}, .{});
    }

    pub fn create(self: *Project) !void {
        var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
        defer auth_manifest.deinit();
        var stdin_buf: [128]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        const project_release = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Name*: ",
            .{ .required = true },
        );
        const project_description = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Description: ",
            .{},
        );
        const project_docs = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Docs: ",
            .{},
        );
        const project_tags = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Tags (seperated by ,): ",
            .{},
        );
        const ProjectPayload = struct {
            name: []const u8,
            tags: []const u8,
            docs: []const u8,
            description: []const u8,
        };
        const project_payload = ProjectPayload{
            .name = project_release,
            .docs = project_docs,
            .description = project_description,
            .tags = project_tags,
        };
        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();
        const project_response = try self.ctx.fetcher.fetch(
            "http://localhost:5000/api/post/project",
            &client,
            .{
                .headers = &.{
                    std.http.Header{
                        .name = "Bearer",
                        .value = auth_manifest.value.token,
                    },
                },
                .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, project_payload, .{}),
            },
        );
        defer project_response.deinit();
        const project_object = project_response.value.object;
        const is_project_successful = project_object.get("success") orelse return;
        if (!is_project_successful.bool) {
            return;
        }
    }
};
