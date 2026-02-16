const std = @import("std");

const Cache = @import("../../lib/functions/cache.zig");
const Context = @import("context");

const Errors = @import("errors");
const CErrors = @import("../errors.zig");

fn cacheClean(ctx: *Context, cache: *Cache) void {
    const cache_name = if (ctx.cmds.len < 4) null else ctx.cmds[3];
    cache.cleanAll(cache_name) catch |err| CErrors.handleCacheError(ctx, err, "clean");
}

fn cacheSize(ctx: *Context, cache: *Cache) void {
    cache.size() catch |err| CErrors.handleCacheError(ctx, err, "size");
}

fn cacheList(ctx: *Context, cache: *Cache) void {
    cache.list() catch |err| CErrors.handleCacheError(ctx, err, "list");
}

pub fn _cacheController(ctx: *Context) !void {
    if (ctx.cmds.len < 3) return Errors.Controller.MissingSubcommand.Cache;

    var cache = Cache.init(ctx);
    defer cache.deinit();

    const arg = ctx.cmds[2];
    if (std.mem.eql(u8, arg, "size")) {
        cacheSize(ctx, &cache);
    } else if (std.mem.eql(u8, arg, "clean")) {
        cacheClean(ctx, &cache);
    } else if (std.mem.eql(u8, arg, "list") or std.mem.eql(u8, arg, "ls")) {
        cacheList(ctx, &cache);
    } else {
        return Errors.Controller.MissingSubcommand.Cache;
    }
}
