const std = @import("std");
const builtin = @import("builtin");

pub const Auth = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Errors = @import("errors");

const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest;
const Fetch = @import("core").Fetch;

const Context = @import("context");
const mvzr = @import("mvzr");

fn verifyEmail(a: []const u8) bool {
    const email_patt = "^[A-Za-z0-9\\.]+@([A-Za-z0-9]+\\.)+[a-z]{2,4}$";
    const email_regex = mvzr.compile(email_patt).?;
    return email_regex.isMatch(a);
}

fn verifyUsername(a: []const u8) bool {
    const username_patt = "^[a-zA-Z0-9_]{3,}";
    const username_regex = mvzr.compile(username_patt).?;
    if (!username_regex.isMatch(a)) return false;

    const allocator = std.heap.page_allocator;
    var body = std.Io.Writer.Allocating.init(allocator);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = std.fmt.allocPrint(
        allocator,
        Constants.Default.zep_url ++ "/api/v1/user?name={s}",
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

pub fn init(ctx: *Context) Auth {
    return Auth{
        .ctx = ctx,
    };
}

fn getUserData(self: *Auth) Errors.Auth!Structs.Fetch.User {
    self.ctx.logger.info("Fetching User Data", @src());

    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Auth.ManifestFailed;
    defer manifest.deinit();
    if (manifest.value.token.len == 0) {
        self.ctx.logger.info("Not Authenticated", @src());
        return Errors.Auth.NotAuthed;
    }

    const get = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/whoami",
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = try manifest.value.bearer(),
                },
            },
        },
    ) catch return Errors.Auth.FetchFailed;
    defer get.deinit();
    const object = get.value.object;
    const success = object.get("success") orelse return Errors.Auth.FetchFailed;
    if (!success.bool) return Errors.Auth.FetchFailed;

    const object_user = object.get("user") orelse return Errors.Auth.FetchFailed;
    const user = object_user.object;

    const user_id = user.get("id") orelse return Errors.Auth.FetchFailed;
    const user_username = user.get("username") orelse return Errors.Auth.FetchFailed;
    const user_email = user.get("email") orelse return Errors.Auth.FetchFailed;
    const user_created_at = user.get("created_at") orelse return Errors.Auth.FetchFailed;
    const parsed = Structs.Fetch.User{
        .Id = user_id.string,
        .Username = user_username.string,
        .Email = user_email.string,
        .CreatedAt = user_created_at.string,
    };

    return parsed;
}

pub fn whoami(self: *Auth) Errors.Auth!void {
    self.ctx.logger.info("Authenticating (Whoami)", @src());

    const user = try self.getUserData();
    self.ctx.printer.append(" - {s}\n", .{user.Username}, .{ .color = .bright_blue });
    self.ctx.printer.append("   > id: {s}\n", .{user.Id}, .{});
    self.ctx.printer.append("   > email: {s}\n", .{user.Email}, .{});
    self.ctx.printer.append("   > created at: {s}\n\n", .{user.CreatedAt}, .{});
}

pub fn register(self: *Auth) Errors.Auth!void {
    self.ctx.logger.info("Authenticating (Registering in)", @src());

    blk: {
        _ = self.getUserData() catch break :blk;
        return Errors.Auth.AlreadyAuthed;
    }

    self.ctx.printer.append("Register:\n\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const username = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter username*: ",
        .{
            .required = true,
            .validate = &verifyUsername,
            .invalid_error_msg = "(invalid / occupied) username",
        },
    ) catch return Errors.Auth.OutOfMemory;

    const email = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter email*: ",
        .{
            .required = true,
            .validate = &verifyEmail,
            .invalid_error_msg = "invalid email",
        },
    ) catch return Errors.Auth.OutOfMemory;

    blk: {
        const url = try std.fmt.allocPrint(
            self.ctx.allocator,
            Constants.Default.zep_url ++ "/api/v1/user?email={s}",
            .{email},
        );
        defer self.ctx.allocator.free(url);
        const get = self.ctx.fetcher.fetch(
            url,
            .{ .method = .GET },
        ) catch |err| {
            switch (err) {
                error.NotFound => break :blk, // if not found, then email is not in use (good)
                else => return Errors.Auth.FetchFailed,
            }
        };

        const object = get.value.object;
        const success = object.get("success") orelse return Errors.Auth.FetchFailed;
        if (success.bool) {
            self.ctx.logger.info("Email already in use", @src());
            self.ctx.printer.append("\nEmail already in use! Login via\n $ zep auth login\n\n", .{}, .{});
            return Errors.Auth.EmailInUse;
        }
    }

    const password = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter password*: ",
        .{
            .required = true,
            .password = true,
        },
    ) catch return Errors.Auth.OutOfMemory;

    const repeat_password = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Repeat password*: ",
        .{
            .required = true,
            .compare = password,
            .invalid_error_msg = "passwords do not match.",
            .password = true,
        },
    ) catch return Errors.Auth.OutOfMemory;
    if (std.mem.eql(u8, repeat_password, password)) return Errors.Auth.PasswordMismatch;

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
    const register_stringified_payload = std.json.Stringify.valueAlloc(
        self.ctx.allocator,
        register_payload,
        .{},
    ) catch return Errors.Auth.ParseFailed;
    defer self.ctx.allocator.free(register_stringified_payload);

    const register_response = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/register",
        .{
            .headers = &.{
                std.http.Header{
                    .name = "Content-Type",
                    .value = "application/json",
                },
            },
            .payload = register_stringified_payload,
        },
    ) catch return Errors.Auth.FetchFailed;

    defer register_response.deinit();
    const register_object = register_response.value.object;
    const is_register_successful = register_object.get("success") orelse return Errors.Auth.FetchFailed;
    if (!is_register_successful.bool) {
        self.ctx.logger.info("Registering failed", @src());
        self.ctx.printer.append(
            "Register failed.\n",
            .{},
            .{
                .color = .red,
                .weight = .bold,
            },
        );
        return;
    }

    const code = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        "Enter code (from mail): ",
        .{
            .required = true,
        },
    ) catch return Errors.Auth.OutOfMemory;
    const VerifyPayload = struct {
        code: []const u8,
        email: []const u8,
    };
    const verify_payload = VerifyPayload{
        .code = code,
        .email = email,
    };
    const verify_stringified_payload = std.json.Stringify.valueAlloc(
        self.ctx.allocator,
        verify_payload,
        .{},
    ) catch return Errors.Auth.ParseFailed;
    defer self.ctx.allocator.free(verify_stringified_payload);

    const verify_response = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/verify",
        .{
            .headers = &.{
                std.http.Header{
                    .name = "Content-Type",
                    .value = "application/json",
                },
            },
            .payload = verify_stringified_payload,
        },
    ) catch return Errors.Auth.FetchFailed;
    defer verify_response.deinit();
    const verify_object = verify_response.value.object;
    const is_verify_successful = verify_object.get("success") orelse return Errors.Auth.FetchFailed;
    if (!is_verify_successful.bool) {
        self.ctx.logger.info("Invalid code entered.", @src());
        self.ctx.printer.append(
            "Invalid code.\n",
            .{},
            .{
                .color = .red,
                .weight = .bold,
            },
        );
        return;
    }
    self.ctx.printer.append("Verified.\n", .{}, .{});

    const jwt_token = verify_object.get("jwt") orelse return Errors.Auth.FetchFailed;
    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Auth.ManifestFailed;
    defer manifest.deinit();
    manifest.value.token = jwt_token.string;
    self.ctx.manifest.writeManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
        manifest.value,
    ) catch return Errors.Auth.ManifestFailed;
    self.ctx.logger.info("User authenticated...", @src());
    self.ctx.printer.append("Logged in.\n", .{}, .{});
}

pub fn login(self: *Auth) Errors.Auth!void {
    self.ctx.logger.info("Authenticating (Logging in)", @src());

    blk: {
        _ = self.getUserData() catch break :blk;
        return Errors.Auth.AlreadyAuthed;
    }

    self.ctx.printer.append("Login:\n", .{}, .{
        .color = .yellow,
        .weight = .bold,
    });

    const email = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter email: ",
        .{
            .required = true,
            .validate = &verifyEmail,
            .invalid_error_msg = "invalid email",
        },
    ) catch return Errors.Auth.OutOfMemory;
    const password = Prompt.input(
        self.ctx.allocator,
        &self.ctx.printer,
        " > Enter password: ",
        .{
            .required = true,
            .password = true,
        },
    ) catch return Errors.Auth.OutOfMemory;

    const AuthPayload = struct {
        email: []const u8,
        password: []const u8,
    };
    const login_payload = AuthPayload{
        .email = email,
        .password = password,
    };
    const login_stringified_payload = std.json.Stringify.valueAlloc(
        self.ctx.allocator,
        login_payload,
        .{},
    ) catch return Errors.Auth.ParseFailed;
    defer self.ctx.allocator.free(login_stringified_payload);

    const login_response = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/login",
        .{
            .headers = &.{
                std.http.Header{
                    .name = "Content-Type",
                    .value = "application/json",
                },
            },
            .payload = login_stringified_payload,
        },
    ) catch return Errors.Auth.FetchFailed;
    defer login_response.deinit();
    const login_object = login_response.value.object;
    const is_login_successful = login_object.get("success") orelse return Errors.Auth.FetchFailed;
    if (!is_login_successful.bool) {
        self.ctx.logger.info("Invalid password entered.", @src());
        return Errors.Auth.InvalidPassword;
    }

    const token = login_object.get("jwt") orelse return Errors.Auth.FetchFailed;
    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Auth.ManifestFailed;
    defer manifest.deinit();
    manifest.value.token = token.string;
    self.ctx.manifest.writeManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
        manifest.value,
    ) catch return Errors.Auth.ManifestFailed;

    self.ctx.printer.append("Logged in.\n", .{}, .{});
    self.ctx.logger.info("User authenticated...", @src());
}

pub fn logout(self: *Auth) Errors.Auth!void {
    self.ctx.logger.info("Logging out", @src());

    var is_error = false;
    _ = self.getUserData() catch {
        is_error = true;
    };
    if (!is_error) return Errors.Auth.NotAuthed;

    var manifest = self.ctx.manifest.readManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
    ) catch return Errors.Auth.ManifestFailed;
    defer manifest.deinit();
    const bearer = manifest.value.bearer() catch return Errors.Auth.FetchFailed;
    manifest.value.token = "";
    self.ctx.manifest.writeManifest(
        Structs.Manifests.Auth,
        self.ctx.paths.auth_manifest,
        manifest.value,
    ) catch return Errors.Auth.ManifestFailed;

    const logout_response = self.ctx.fetcher.fetch(
        Constants.Default.zep_url ++ "/api/v1/logout",
        .{
            .method = .GET,
            .headers = &.{
                std.http.Header{
                    .name = "Authorization",
                    .value = bearer,
                },
            },
        },
    ) catch return Errors.Auth.FetchFailed;
    defer logout_response.deinit();
    const logout_object = logout_response.value.object;
    const logout_success = logout_object.get("success") orelse return Errors.Auth.FetchFailed;
    if (!logout_success.bool) {
        self.ctx.logger.info("Logout failed.", @src());
        return Errors.Auth.FetchFailed;
    }

    self.ctx.printer.append("Logged out.\n", .{}, .{});
    self.ctx.logger.info("User Logged out...", @src());
}
