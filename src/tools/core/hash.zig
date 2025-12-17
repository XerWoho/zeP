const std = @import("std");
const Constants = @import("constants");
const Logger = @import("logger");

/// Get hash from any url
pub fn hashData(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const logger = Logger.get();
    const start = std.time.milliTimestamp();

    try logger.debugf("hashData: start url={s}", .{url}, @src());

    const uri = std.Uri.parse(url) catch |err| {
        try logger.warnf("hashData: invalid url={s} err={}", .{ url, err }, @src());
        return error.InvalidUrl;
    };

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(allocator);

    try logger.debugf("hashData: fetching url={s}", .{url}, @src());

    const fetched = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &body.writer,
    }) catch |err| {
        try logger.errorf("hashData: fetch failed url={s} err={}", .{ url, err }, @src());
        return err;
    };

    if (fetched.status == .not_found) {
        try logger.warnf("hashData: 404 url={s}", .{url}, @src());
        return error.NotFound;
    }

    const data = body.written();
    hasher.update(data);

    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    const out = try std.fmt.allocPrint(allocator, "{x}", .{hash});

    const elapsed = std.time.milliTimestamp() - start;
    try logger.debugf(
        "hashData: done url={s} bytes={} time={}ms",
        .{ url, data.len, elapsed },
        @src(),
    );

    return out;
}
