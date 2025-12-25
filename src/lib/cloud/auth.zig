const std = @import("std");
const builtin = @import("builtin");

const Constants = @import("constants");
const Structs = @import("structs");

const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Manifest = @import("core").Manifest;
const Fetch = @import("core").Fetch;

const Context = @import("context").Context;

/// Handles Auth
pub const Auth = struct {
    ctx: *Context,

    pub fn init(
        ctx: *Context,
    ) !Auth {
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
            "http://localhost:5000/api/get/profile",
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
        const user = try self.getUserData();
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

        var stdin_buf: [128]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        const username = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Enter username: ",
            .{
                .required = true,
            },
        );
        const email = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Enter email: ",
            .{
                .required = true,
            },
        );
        const password = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Enter password: ",
            .{
                .required = true,
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

        var client = std.http.Client{ .allocator = self.ctx.allocator };
        defer client.deinit();
        const register_response = try self.ctx.fetcher.fetch(
            "http://localhost:5000/api/auth/register",
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
            stdin,
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
            "http://localhost:5000/api/auth/verify",
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
        var stdin_buf: [128]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        const email = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Enter email: ",
            .{
                .required = true,
            },
        );
        const password = try Prompt.input(
            self.ctx.allocator,
            &self.ctx.printer,
            stdin,
            " > Enter password: ",
            .{
                .required = true,
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
            "http://localhost:5000/api/auth/login",
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
            "http://localhost:5000/api/auth/logout",
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
};
