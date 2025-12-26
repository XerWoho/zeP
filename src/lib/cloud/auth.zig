const std = @import("std");
const builtin = @import("builtin");

pub const Auth = @This();

const Constants = @import("constants");
const Structs = @import("structs");

const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest;
const Fetch = @import("core").Fetch;

const Context = @import("context");

const mvzr = @import("mvzr");
fn verifyEmail(a: []const u8) bool {
    const email_patt = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}";
    const email_regex = mvzr.compile(email_patt).?;
    return email_regex.isMatch(a);
}

fn verifyUsername(a: []const u8) bool {
    const username_patt = "^[a-zA-Z0-9]{3,}";
    const username_regex = mvzr.compile(username_patt).?;
    if (!username_regex.isMatch(a)) return false;

    const allocator = std.heap.page_allocator;
    var body = std.Io.Writer.Allocating.init(allocator);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = std.fmt.allocPrint(
        allocator,
        Constants.Default.zep_url ++ "/api/get/name?name={s}",
        .{a},
    ) catch return false;
    defer allocator.free(url);
    const f = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &body.writer,
    }) catch return false;
    return f.status != .ok;
}

/// Handles Auth
ctx: *Context,

pub fn init(ctx: *Context) !Auth {
    return Auth{
        .ctx = ctx,
    };
}

const FetchOptions = struct {
    payload: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
    method: std.http.Method = .POST,
};

const User = struct {
    Id: []const u8,
    Username: []const u8,
    Email: []const u8,
    CreatedAt: []const u8,
};

fn getUserData(self: *Auth) !std.json.Parsed(User) {
    var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
    defer auth_manifest.deinit();
    if (auth_manifest.value.token.len == 0) return error.NotAuthed;

    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();
    const profile_response = try self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/whoami",
        &client,
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Bearer",
                    .value = auth_manifest.value.token,
                },
            },
        },
    );
    defer profile_response.deinit();
    const profile_object = profile_response.value.object;
    const is_profile_success = profile_object.get("success") orelse return error.FetchFailed;
    if (!is_profile_success.bool) {
        return error.FetchFailed;
    }

    const user = profile_object.get("user") orelse return error.FetchFailed;
    const encoded = user.string;
    const decoded = try self.ctx.allocator.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
    try std.base64.standard.Decoder.decode(decoded, encoded);
    const parsed: std.json.Parsed(User) = try std.json.parseFromSlice(User, self.ctx.allocator, decoded, .{});
    return parsed;
}

pub fn whoami(self: *Auth) !void {
    const user = self.getUserData() catch |err| {
        switch (err) {
            error.NotAuthed => {
                try self.ctx.printer.append(
                    "Not authenticated.\n",
                    .{},
                    .{ .color = .bright_red },
                );
                return;
            },
            else => return err,
        }
    };
    defer user.deinit();

    try self.ctx.printer.append(" - {s}\n", .{user.value.Username}, .{ .color = .bright_blue });
    try self.ctx.printer.append("   > id: {s}\n", .{user.value.Id}, .{});
    try self.ctx.printer.append("   > email: {s}\n", .{user.value.Email}, .{});
    try self.ctx.printer.append("   > created at: {s}\n\n", .{user.value.CreatedAt}, .{});
}

pub fn register(self: *Auth) !void {
    blk: {
        var is_error = false;
        _ = self.getUserData() catch {
            is_error = true;
        };
        if (is_error) break :blk;
        return;
    }

    try self.ctx.printer.append("--- REGISTER MODE ---\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const username = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter username*: ",
        .{
            .required = true,
            .validate = &verifyUsername,
            .invalid_error_msg = "(invalid / occupied) username",
        },
    );

    const email = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter email*: ",
        .{
            .required = true,
            .validate = &verifyEmail,
            .invalid_error_msg = "invalid email",
        },
    );

    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();

    blk: {
        const url = try std.fmt.allocPrint(
            self.ctx.allocator,
            Constants.Default.zep_url ++ "/api/get/email?email={s}",
            .{email},
        );
        defer self.ctx.allocator.free(url);
        const check = self.ctx.fetcher.fetch(url, &client, .{ .method = .GET }) catch |err| {
            switch (err) {
                error.NotFound => break :blk,
                else => return err,
            }
        };

        const obj = check.value.object;
        const success = obj.get("success") orelse return error.InvalidFetch;
        if (success.bool) {
            try self.ctx.printer.append("\nEmail already in use! Login via\n $ zep auth login\n\n", .{}, .{});
            return;
        }
    }

    const password = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter password*: ",
        .{
            .required = true,
            .password = true,
        },
    );

    _ = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Repeat password*: ",
        .{
            .required = true,
            .compare = password,
            .invalid_error_msg = "passwords do not match.",
            .password = true,
        },
    );

    const RegisterPayload = struct {
        username: []const u8,
        email: []const u8,
        password: []const u8,
    };
    const register_payload = RegisterPayload{
        .username = username,
        .email = email,
        .password = password,
    };

    const register_response = try self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/auth/register",
        &client,
        .{ .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, register_payload, .{}) },
    );
    defer register_response.deinit();
    const register_object = register_response.value.object;
    const is_register_successful = register_object.get("success") orelse return;
    if (!is_register_successful.bool) {
        return;
    }

    const code = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "Enter code (from mail): ",
        .{
            .required = true,
        },
    );
    const VerifyPayload = struct {
        code: []const u8,
        email: []const u8,
    };
    const verify_payload = VerifyPayload{
        .code = code,
        .email = email,
    };
    const verify_response = try self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/auth/verify",
        &client,
        .{
            .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, verify_payload, .{}),
        },
    );
    defer verify_response.deinit();
    const verify_object = verify_response.value.object;
    const is_verify_successful = verify_object.get("success") orelse return;
    if (!is_verify_successful.bool) {
        return;
    }
    const jwt_token = verify_object.get("jwt") orelse return;
    var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
    defer auth_manifest.deinit();
    auth_manifest.value.token = jwt_token.string;
    try self.ctx.manifest.writeManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest, auth_manifest.value);
}

pub fn login(self: *Auth) !void {
    try self.ctx.printer.append("--- LOGIN MODE ---\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const email = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter email: ",
        .{
            .required = true,
            .validate = &verifyEmail,
            .invalid_error_msg = "invalid email",
        },
    );
    const password = try Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter password: ",
        .{
            .required = true,
            .password = true,
        },
    );

    const AuthPayload = struct {
        email: []const u8,
        password: []const u8,
    };
    const login_payload = AuthPayload{
        .email = email,
        .password = password,
    };

    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();

    const login_response = try self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/auth/login",
        &client,
        .{ .payload = try std.json.Stringify.valueAlloc(self.ctx.allocator, login_payload, .{}) },
    );
    defer login_response.deinit();
    const login_object = login_response.value.object;
    const is_login_successful = login_object.get("success") orelse return;
    if (!is_login_successful.bool) {
        return;
    }

    const token = login_object.get("jwt") orelse {
        return;
    };
    var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
    defer auth_manifest.deinit();
    auth_manifest.value.token = token.string;
    try self.ctx.manifest.writeManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest, auth_manifest.value);
}

pub fn logout(self: *Auth) !void {
    var auth_manifest = try self.ctx.manifest.readManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest);
    defer auth_manifest.deinit();

    var client = std.http.Client{ .allocator = self.ctx.allocator };
    defer client.deinit();
    const logout_response = try self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/auth/logout",
        &client,
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Bearer",
                    .value = auth_manifest.value.token,
                },
            },
        },
    );
    defer logout_response.deinit();
    const logout_object = logout_response.value.object;
    const logout_success = logout_object.get("success") orelse return error.FetchFailed;
    if (!logout_success.bool) {
        return error.FetchFailed;
    }

    auth_manifest.value.token = "";
    try self.ctx.manifest.writeManifest(Structs.Manifests.AuthManifest, self.ctx.paths.auth_manifest, auth_manifest.value);
}
