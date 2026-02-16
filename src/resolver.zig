const std = @import("std");

pub const Resolver = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Errors = @import("errors");

const Hash = @import("core").Hash;
const Json = @import("core").Json;
const Fs = @import("io").Fs;

const Context = @import("context").Context;

ctx: *Context,

pub fn init(ctx: *Context) Resolver {
    return Resolver{
        .ctx = ctx,
    };
}

fn loadCached(
    self: *Resolver,
    path: []const u8,
) !?Structs.Packages.Package {
    if (!Fs.existsFile(path)) return null;

    const f = try Fs.openFile(path);
    defer f.close();

    const data = try f.readToEndAlloc(self.ctx.allocator, Constants.Default.mb * 5);
    defer self.ctx.allocator.free(data);

    var parsed: std.json.Parsed(Structs.Packages.Package) = try std.json.parseFromSlice(
        Structs.Packages.Package,
        self.ctx.allocator,
        data,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    return try parsed.value.dupPackage(self.ctx.allocator);
}

fn storeCached(
    self: *Resolver,
    path: []const u8,
    pkg: Structs.Packages.Package,
) !void {
    const f = try Fs.createFile(path);
    defer f.close();

    const data = try std.json.Stringify.valueAlloc(self.ctx.allocator, pkg, .{});
    defer self.ctx.allocator.free(data);

    _ = try f.writeAll(data);
}

fn selectVersion(
    versions: []Structs.Packages.Version,
    requested: ?[]const u8,
) !Structs.Packages.Version {
    if (versions.len == 0) return Errors.Installable.InvalidPackage;

    const target = requested orelse "latest";
    if (std.mem.eql(u8, target, "latest")) return versions[0];

    for (versions) |v| {
        if (std.mem.eql(u8, v.version, target)) return v;
    }

    return Errors.Installable.VersionNotFound;
}

fn makeVersion(
    self: *Resolver,
    options: struct {
        url: []const u8 = "",
        version: []const u8 = "",
        zig_version: []const u8 = "/",
        root_file: []const u8 = "/",
        sha256sum: []const u8 = "",
    },
) !Structs.Packages.Version {
    return .{
        .url = try self.ctx.allocator.dupe(u8, options.url),
        .version = try self.ctx.allocator.dupe(u8, options.version),
        .zig_version = try self.ctx.allocator.dupe(u8, options.zig_version),
        .root_file = try self.ctx.allocator.dupe(u8, options.root_file),
        .sha256sum = try self.ctx.allocator.dupe(u8, options.sha256sum),
    };
}

fn resolveFromLock(
    self: *Resolver,
    name: []const u8,
    version: []const u8,
) !?Structs.ZepFiles.Package {
    const lock = try self.ctx.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();

    for (lock.value.packages) |p| {
        if (!std.mem.eql(u8, p.name, name)) continue;
        if (!std.mem.eql(u8, p.version, version)) continue;
        self.ctx.logger.info("Package found in .lock...", @src());

        return Structs.ZepFiles.Package{
            .name = try self.ctx.allocator.dupe(u8, p.name),
            .version = try self.ctx.allocator.dupe(u8, p.version),
            .install = try self.ctx.allocator.dupe(u8, p.install),
            .author = try self.ctx.allocator.dupe(u8, p.author),
            .source = try self.ctx.allocator.dupe(u8, p.source),
            .zig_version = try self.ctx.allocator.dupe(u8, p.zig_version),
            .hash = try self.ctx.allocator.dupe(u8, p.hash),
            .namespace = p.namespace,
        };
    }

    return null;
}

fn resolveFromFetch(
    self: *Resolver,
    name: []const u8,
    version: ?[]const u8,
    namespace: Structs.Extras.Namespaces,
) !Structs.ZepFiles.Package {
    self.ctx.logger.info("Fetching package version...", @src());
    self.ctx.printer.append("Finding the package...\n", .{}, .{
        .verbosity = 3,
    });
    var package = self.fetchPackage(
        name,
        namespace,
    ) catch return Errors.Installable.FetchFailed;
    defer package.deinit(self.ctx.allocator);
    self.ctx.logger.infof("Package fetched!", .{}, @src());

    self.ctx.printer.append(
        " > PACKAGE FOUND\n\n",
        .{},
        .{
            .color = .green,
            .verbosity = 2,
        },
    );

    const versions = package.versions;
    var v = try selectVersion(
        versions,
        version,
    );

    if (v.sha256sum.len == 0) {
        const hash = Hash.hashDataByUrl(
            self.ctx.allocator,
            v.url,
        ) catch return Errors.Installable.HashFailed;
        v.sha256sum = hash;
    }

    return Structs.ZepFiles.Package{
        .name = try self.ctx.allocator.dupe(u8, package.name),
        .author = try self.ctx.allocator.dupe(u8, package.author),
        .install = try std.fmt.allocPrint(self.ctx.allocator, "{s}@{s}", .{ name, v.version }),
        .version = try self.ctx.allocator.dupe(u8, v.version),
        .namespace = namespace,
        .source = try self.ctx.allocator.dupe(u8, v.url),
        .zig_version = try self.ctx.allocator.dupe(u8, v.zig_version),
        .hash = try self.ctx.allocator.dupe(u8, v.sha256sum),
    };
}

pub fn resolve(
    self: *Resolver,
    name: []const u8,
    version: ?[]const u8,
    namespace: Structs.Extras.Namespaces,
) Errors.Installable!Structs.ZepFiles.Package {
    if (version) |v| {
        const attempt = self.resolveFromLock(
            name,
            v,
        ) catch return Errors.Installable.ResolveFailed;
        if (attempt) |a| return a;
    }

    const i_type = namespace;
    const package = self.resolveFromFetch(
        name,
        version,
        i_type,
    ) catch return Errors.Installable.FetchFailed;

    self.ctx.logger.infof(
        "Package version = {s}!",
        .{package.version},
        @src(),
    );
    return package;
}

fn fetchFromZep(
    self: *Resolver,
    name: []const u8,
) Errors.Installable!Structs.Packages.Package {
    const cached_filename = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/zep+{s}.json",
        .{ self.ctx.paths.meta_cached, name },
    );
    defer self.ctx.allocator.free(cached_filename);
    const loaded_from_cache = self.loadCached(cached_filename) catch return Errors.Installable.CacheFailed;
    if (loaded_from_cache) |p| return p;

    var releases = self.ctx.fetcher.fetchReleases(name) catch return Errors.Installable.FetchFailed;
    defer releases.deinit(self.ctx.allocator);

    var versions = try self.ctx.allocator.alloc(
        Structs.Packages.Version,
        releases.items.len,
    );
    for (releases.items, 0..) |r, i| {
        versions[i] = try self.makeVersion(.{
            .root_file = r.RootFile,
            .sha256sum = r.Hash,
            .url = r.Url,
            .version = r.Release,
            .zig_version = r.ZigVersion,
        });
    }

    const fetched = self.ctx.fetcher.fetchPackage(name) catch return Errors.Installable.FetchFailed;
    const package = Structs.Packages.Package{
        .author = try self.ctx.allocator.dupe(u8, fetched.UserID),
        .name = try self.ctx.allocator.dupe(u8, fetched.Name),
        .docs = try self.ctx.allocator.dupe(u8, fetched.Docs),
        .versions = versions,
    };

    self.storeCached(
        cached_filename,
        package,
    ) catch return Errors.Installable.CacheFailed;
    return package;
}

fn fetchFromZepUrl(
    self: *Resolver,
    name: []const u8,
) Errors.Installable!Structs.Packages.Package {
    const cached_filename = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/zepu+{s}.json",
        .{ self.ctx.paths.meta_cached, name },
    );
    defer self.ctx.allocator.free(cached_filename);
    const loaded_from_cache = self.loadCached(cached_filename) catch return Errors.Installable.CacheFailed;
    if (loaded_from_cache) |p| return p;

    const url = try std.fmt.allocPrint(
        self.ctx.allocator,
        Constants.Default.zep_url ++ "/packages/{s}.json",
        .{name},
    );
    defer self.ctx.allocator.free(url);
    var package = self.ctx.fetcher.fetchJson(url, Structs.Packages.Package) catch return Errors.Installable.FetchFailed;
    defer package.deinit();

    const p = try package.value.dupPackage(self.ctx.allocator);
    self.storeCached(
        cached_filename,
        p,
    ) catch return Errors.Installable.CacheFailed;
    return p;
}

fn fetchDefaultBranch(self: *Resolver, url: []const u8) Errors.Installable![]const u8 {
    const DefaultBranch = struct { default_branch: []const u8 };

    const default_branch = self.ctx.fetcher.fetchJson(url, DefaultBranch) catch return Errors.Installable.FetchFailed;
    defer default_branch.deinit();
    return try self.ctx.allocator.dupe(u8, default_branch.value.default_branch);
}

fn fetchFromGithub(
    self: *Resolver,
    package_install: []const u8,
) !Structs.Packages.Package {
    var p_split = std.mem.splitAny(u8, package_install, "/");
    const owner = p_split.next() orelse return Errors.Installable.PackageNotFound;
    const repo = p_split.next() orelse return Errors.Installable.PackageNotFound;

    const cached_filename = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/github+{s}.json",
        .{ self.ctx.paths.meta_cached, repo },
    );
    defer self.ctx.allocator.free(cached_filename);
    const loaded_from_cache = self.loadCached(cached_filename) catch return Errors.Installable.CacheFailed;
    if (loaded_from_cache) |p| return p;

    const GithubPackage = struct {
        zipball_url: []const u8,
        author: struct { login: []const u8 },
        tag_name: []const u8,
    };

    const url = try std.fmt.allocPrint(self.ctx.allocator, "{s}/repos/{s}/{s}/releases", .{
        Constants.Default.github_api,
        owner,
        repo,
    });
    defer self.ctx.allocator.free(url);
    var github_package_releases = self.ctx.fetcher.fetchJson(url, []GithubPackage) catch return Errors.Installable.FetchFailed;
    defer github_package_releases.deinit();

    const releases = github_package_releases.value;
    var versions = try self.ctx.allocator.alloc(
        Structs.Packages.Version,
        if (releases.len > 0) releases.len else 1,
    );

    for (releases, 0..) |gpr, i| {
        const source = try std.fmt.allocPrint(
            self.ctx.allocator,
            "{s}#.zip",
            .{gpr.zipball_url},
        );
        versions[i] = try self.makeVersion(.{
            .url = source,
            .version = gpr.tag_name,
        });
    }

    if (github_package_releases.value.len == 0) {
        const selfurl = try std.fmt.allocPrint(self.ctx.allocator, "{s}/repos/{s}/{s}", .{
            Constants.Default.github_api,
            owner,
            repo,
        });
        defer self.ctx.allocator.free(selfurl);
        const default_branch = try self.fetchDefaultBranch(selfurl);
        defer self.ctx.allocator.free(default_branch);

        const fmt = "https://github.com/{s}/{s}/archive/refs/heads/{s}.zip";
        const modurl = try std.fmt.allocPrint(self.ctx.allocator, fmt, .{ owner, repo, default_branch });
        versions[0] = try self.makeVersion(
            .{
                .url = modurl,
                .version = "latest",
            },
        );
    }

    const package = Structs.Packages.Package{
        .author = try self.ctx.allocator.dupe(u8, owner),
        .name = try self.ctx.allocator.dupe(u8, repo),
        .docs = "",
        .versions = versions,
    };

    self.storeCached(
        cached_filename,
        package,
    ) catch return Errors.Installable.CacheFailed;
    return package;
}

fn fetchFromGitlab(
    self: *Resolver,
    package_install: []const u8,
) !Structs.Packages.Package {
    var p_split = std.mem.splitAny(u8, package_install, "/");
    const owner = p_split.next() orelse return Errors.Installable.PackageNotFound;
    var repo = p_split.next() orelse return Errors.Installable.PackageNotFound;
    while (p_split.next()) |p| {
        repo = p;
    }

    const size = std.mem.replacementSize(u8, package_install, "/", "%2F");
    const install = try self.ctx.allocator.alloc(u8, size);
    defer self.ctx.allocator.free(install);
    _ = std.mem.replace(u8, package_install, "/", "%2F", install);

    const cached_filename = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/gitlab+{s}.json",
        .{ self.ctx.paths.meta_cached, repo },
    );
    defer self.ctx.allocator.free(cached_filename);
    const loaded_from_cache = self.loadCached(cached_filename) catch return Errors.Installable.CacheFailed;
    if (loaded_from_cache) |p| return p;

    const GitlabPackage = struct {
        name: []const u8,
        assets: struct { sources: []struct {
            format: []const u8,
            url: []const u8,
        } },
        author: struct { username: []const u8 },
    };

    const url = try std.fmt.allocPrint(self.ctx.allocator, "{s}/projects/{s}/releases", .{
        Constants.Default.gitlab_api,
        install,
    });
    defer self.ctx.allocator.free(url);
    const gitlab_package_releases = self.ctx.fetcher.fetchJson(url, []GitlabPackage) catch return Errors.Installable.FetchFailed;
    defer gitlab_package_releases.deinit();

    const releases = gitlab_package_releases.value;

    var versions = try self.ctx.allocator.alloc(
        Structs.Packages.Version,
        if (releases.len > 0) releases.len else 1,
    );

    for (releases, 0..) |gpr, i| {
        for (gpr.assets.sources) |s| {
            if (!std.mem.eql(u8, "zip", s.format)) continue;

            versions[i] = try self.makeVersion(.{
                .url = s.url,
                .version = gpr.name,
            });
            break;
        }
    }

    if (gitlab_package_releases.value.len == 0) {
        const selfurl = try std.fmt.allocPrint(self.ctx.allocator, "{s}/projects/{s}", .{
            Constants.Default.gitlab_api,
            install,
        });
        defer self.ctx.allocator.free(selfurl);
        const default_branch = try self.fetchDefaultBranch(selfurl);
        defer self.ctx.allocator.free(default_branch);

        const fmt = "https://gitlab.com/{s}/{s}/-/archive/{s}/{s}-{s}.zip?ref_type=heads";
        const modurl = try std.fmt.allocPrint(self.ctx.allocator, fmt, .{ owner, repo, default_branch, repo, default_branch });
        versions[0] = try self.makeVersion(.{
            .url = modurl,
            .version = "latest",
        });
    }

    const package = Structs.Packages.Package{
        .author = try self.ctx.allocator.dupe(u8, owner),
        .name = try self.ctx.allocator.dupe(u8, repo),
        .docs = "",
        .versions = versions,
    };

    self.storeCached(cached_filename, package) catch return Errors.Installable.CacheFailed;
    return package;
}

fn fetchFromCodeberg(
    self: *Resolver,
    package_install: []const u8,
) !Structs.Packages.Package {
    var p_split = std.mem.splitAny(u8, package_install, "/");
    const owner = p_split.next() orelse return Errors.Installable.PackageNotFound;
    const repo = p_split.next() orelse return Errors.Installable.PackageNotFound;

    const cached_filename = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/codeberg+{s}.json",
        .{ self.ctx.paths.meta_cached, repo },
    );
    defer self.ctx.allocator.free(cached_filename);
    const loaded_from_cache = self.loadCached(cached_filename) catch return Errors.Installable.CacheFailed;
    if (loaded_from_cache) |p| return p;

    const CodebergPackage = struct {
        name: []const u8,
        zipball_url: []const u8,
        author: struct { username: []const u8 },
    };

    const url = try std.fmt.allocPrint(self.ctx.allocator, "{s}/repos/{s}/{s}/releases", .{
        Constants.Default.codeberg_api,
        owner,
        repo,
    });
    defer self.ctx.allocator.free(url);
    const codeberg_package_releases = self.ctx.fetcher.fetchJson(url, []CodebergPackage) catch return Errors.Installable.FetchFailed;

    defer codeberg_package_releases.deinit();

    const releases = codeberg_package_releases.value;

    var versions = try self.ctx.allocator.alloc(
        Structs.Packages.Version,
        if (releases.len == 0) 1 else releases.len,
    );

    for (releases, 0..) |cpr, i| {
        versions[i] = try self.makeVersion(.{
            .url = cpr.zipball_url,
            .version = cpr.name,
        });
    }

    if (releases.len == 0) {
        const selfurl = try std.fmt.allocPrint(
            self.ctx.allocator,
            "{s}/repos/{s}/{s}",
            .{ Constants.Default.codeberg_api, owner, repo },
        );
        defer self.ctx.allocator.free(selfurl);

        const default_branch = try self.fetchDefaultBranch(selfurl);
        defer self.ctx.allocator.free(default_branch);

        const modurl = try std.fmt.allocPrint(
            self.ctx.allocator,
            "https://codeberg.org/{s}/{s}/archive/{s}.zip",
            .{ owner, repo, default_branch },
        );
        defer self.ctx.allocator.free(modurl);

        versions[0] = try self.makeVersion(.{
            .url = modurl,
            .version = "latest",
        });
    }

    const package = Structs.Packages.Package{
        .author = try self.ctx.allocator.dupe(u8, owner),
        .name = try self.ctx.allocator.dupe(u8, repo),
        .docs = "",
        .versions = versions,
    };

    self.storeCached(
        cached_filename,
        package,
    ) catch return Errors.Installable.CacheFailed;

    return package;
}

fn loadFromLocal(
    self: *Resolver,
    name: []const u8,
) !Structs.Packages.Package {
    const path = try std.fmt.allocPrint(
        self.ctx.allocator,
        "{s}/{s}.json",
        .{ self.ctx.paths.custom, name },
    );
    defer self.ctx.allocator.free(path);

    if (!Fs.existsFile(path)) return Errors.Installable.PackageNotFound;

    var package: std.json.Parsed(Structs.Packages.Package) = try Json.parseJsonFromFile(
        self.ctx.allocator,
        Structs.Packages.Package,
        path,
        Constants.Default.mb * 10,
    );
    defer package.deinit();

    const duped = try package.value.dupPackage(self.ctx.allocator);
    return duped;
}

pub fn fetchPackage(
    self: *Resolver,
    package_install: []const u8,
    namespace: Structs.Extras.Namespaces,
) Errors.Installable!Structs.Packages.Package {
    switch (namespace) {
        .zep => {
            const pkg = self.fetchFromZep(package_install) catch {
                const fallback = self.fetchFromZepUrl(package_install) catch return Errors.Installable.FetchFailed;
                return fallback;
            };
            return pkg;
        },
        .local => {
            const pkg = self.loadFromLocal(package_install) catch return Errors.Installable.FetchFailed;
            return pkg;
        },
        .github => {
            const pkg = self.fetchFromGithub(package_install) catch return Errors.Installable.FetchFailed;
            return pkg;
        },
        .gitlab => {
            const pkg = self.fetchFromGitlab(package_install) catch return Errors.Installable.FetchFailed;
            return pkg;
        },
        .codeberg => {
            const pkg = self.fetchFromCodeberg(package_install) catch return Errors.Installable.FetchFailed;
            return pkg;
        },
    }
    return Errors.Installable.PackageNotFound;
}
