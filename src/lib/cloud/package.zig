const std = @import("std");

pub const Package = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Errors = @import("errors");

const Prompt = @import("cli").Prompt;
const Fs = @import("io").Fs;
const Compressor = @import("core").Compressor;

const Context = @import("context");
const mvzr = @import("mvzr");

/// Handles Packages
ctx: *Context,

pub fn init(ctx: *Context) Package {
    return .{
        .ctx = ctx,
    };
}

pub fn delete(self: *Package) Errors.Cloud!void {
    self.ctx.logger.info("Deleting Package", @src());

    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Cloud.ManifestFailed;
    defer manifest.deinit();

    var packages = self.ctx.fetcher.fetchPackages() catch return Errors.Cloud.FetchFailed;
    defer packages.deinit(self.ctx.allocator);

    self.ctx.printer.append("Available packages:\n", .{}, .{});
    if (packages.items.len == 0) {
        self.ctx.printer.append("-- No packages --\n\n", .{}, .{ .color = .bright_red });
        return;
    }
    for (packages.items, 0..) |p, i| {
        self.ctx.printer.append(" [{d}] - {s}\n", .{ i, p.Name }, .{});
    }
    self.ctx.printer.append("\n", .{}, .{});

    const index_str = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "TARGET >> ",
        .{ .required = true },
    ) catch return Errors.Cloud.OutOfMemory;

    const index = std.fmt.parseInt(
        usize,
        index_str,
        10,
    ) catch return Errors.Cloud.InvalidSelection;

    self.ctx.printer.append(
        "Selected: {s}\n\n",
        .{packages.items[index].Name},
        .{ .color = .bright_black },
    );
    if (index >= packages.items.len) {
        self.ctx.logger.info("Invalid Package Selection.", @src());
        return Errors.Cloud.InvalidSelection;
    }

    const target = packages.items[index];
    const target_id = target.ID;

    var releases = self.ctx.fetcher.fetchReleases(target.Name) catch return Errors.Cloud.FetchFailed;
    defer releases.deinit(self.ctx.allocator);
    if (releases.items.len != 0) {
        self.ctx.printer.append(
            "\nSelected package has {d} release(s)\n",
            .{releases.items.len},
            .{
                .color = .red,
                .weight = .bold,
            },
        );
        for (releases.items) |r| {
            self.ctx.printer.append(
                " > {s} {s}\n    ({s})\n",
                .{
                    target.Name,
                    r.Release,
                    r.Hash,
                },
                .{},
            );
        }
        self.ctx.printer.append(
            "\nYou want to continue?\n",
            .{},
            .{},
        );
        const answer = Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            "(y/N) ",
            .{},
        ) catch return Errors.Cloud.OutOfMemory;
        if (answer.len == 0 or
            (!std.mem.startsWith(u8, answer, "y") and
                !std.mem.startsWith(u8, answer, "Y")))
        {
            self.ctx.printer.append("\nOk.\n", .{}, .{});
            return;
        }
    } else {
        self.ctx.printer.append(
            "Deleting package...\n\n",
            .{},
            .{ .color = .red },
        );
    }

    const url = try std.fmt.allocPrint(
        self.ctx.allocator,
        Constants.Default.zep_url ++ "/api/v1/package?id={s}",
        .{target_id},
    );
    defer self.ctx.allocator.free(url);
    const delete_package_response = self.ctx.fetcher.fetch(
        url,
        .{
            .method = .DELETE,
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = try manifest.value.bearer(),
                },
            },
        },
    ) catch return Errors.Cloud.FetchFailed;
    defer delete_package_response.deinit();
    const delete_package_object = delete_package_response.value.object;
    const is_delete_package_successful = delete_package_object.get("success") orelse return;
    if (!is_delete_package_successful.bool) {
        self.ctx.printer.append("Failed.\n", .{}, .{ .color = .red });
        return;
    }
    self.ctx.printer.append("Deleted.\n", .{}, .{});
}

pub fn list(self: *Package) Errors.Cloud!void {
    self.ctx.logger.info("Listing Package", @src());

    var packages = self.ctx.fetcher.fetchPackages() catch return Errors.Cloud.FetchFailed;
    defer packages.deinit(self.ctx.allocator);

    self.ctx.printer.append("Available packages:\n", .{}, .{});
    if (packages.items.len == 0) {
        self.ctx.printer.append("-- No packages --\n\n", .{}, .{ .color = .bright_red });
    }
    for (packages.items) |r| {
        self.ctx.printer.append(" - {s}\n  > {s}\n", .{ r.Name, r.ID }, .{});
    }
    self.ctx.printer.append("\n", .{}, .{});
}

fn packageNameAvailable(package_name: []const u8) bool {
    const package_patt = "^[a-z-]{2,20}";
    const package_regex = mvzr.compile(package_patt).?;
    if (!package_regex.isMatch(package_name)) return false;

    const allocator = std.heap.page_allocator;
    const url = std.fmt.allocPrint(
        allocator,
        Constants.Default.zep_url ++ "/api/v1/package?name={s}",
        .{package_name},
    ) catch return false;
    defer allocator.free(url);
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    const f = client.fetch(
        .{
            .method = .GET,
            .location = .{ .url = url },
        },
    ) catch return false;
    return f.status != .ok;
}

pub fn create(self: *Package) !void {
    self.ctx.logger.info("Creating Package", @src());

    self.ctx.printer.append("Package:\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Cloud.ManifestFailed;
    defer manifest.deinit();
    if (manifest.value.token.len == 0) {
        return Errors.Cloud.NotAuthed;
    }

    const package_name = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Name*: ",
        .{
            .required = true,
            .validate = &packageNameAvailable,
            .invalid_error_msg = "(invalid / occupied) package name",
        },
    ) catch return Errors.Cloud.OutOfMemory;

    const package_docs = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Docs: ",
        .{},
    ) catch return Errors.Cloud.OutOfMemory;

    const PackagePayload = struct {
        package: struct {
            name: []const u8,
            tags: []const u8,
            docs: []const u8,
            description: []const u8,
        },
    };

    const lock = self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    ) catch return Errors.Cloud.ManifestFailed;
    defer lock.deinit();

    const tags = try std.mem.join(self.ctx.allocator, ",", lock.value.root.tags);
    defer self.ctx.allocator.free(tags);

    const package_payload = PackagePayload{
        .package = .{
            .name = package_name,
            .docs = package_docs,
            .description = lock.value.root.description,
            .tags = tags,
        },
    };

    const package_response = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/package",
        .{
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = try manifest.value.bearer(),
                },
                std.http.Header{
                    .name = "Content-Type",
                    .value = "application/json",
                },
            },
            .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, package_payload, .{}),
        },
    ) catch return Errors.Cloud.FetchFailed;
    defer package_response.deinit();
    const package_object = package_response.value.object;
    const is_package_successful = package_object.get("success") orelse return;
    if (!is_package_successful.bool) {
        self.ctx.printer.append("Failed.\n", .{}, .{ .color = .bright_red });
        return;
    }

    self.ctx.printer.append("Created.\n", .{}, .{});
}
