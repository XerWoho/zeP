const std = @import("std");

const Cache = @import("../../lib/functions/cache.zig").Cache;
const Context = @import("context").Context;

fn cacheClean(ctx: *Context, cache: *Cache) !void {
    const cache_name = ctx.args[3];
    try cache.clean(cache_name);
    return;
}

fn cacheSize(ctx: *Context, cache: *Cache) !void {
    _ = ctx;
    try cache.size();
    return;
}

fn cacheList(ctx: *Context, cache: *Cache) !void {
    _ = ctx;
    try cache.list();
    return;
}

pub fn _cacheController(
    ctx: *Context,
) !void {
    if (ctx.args.len < 3) return error.MissingSubcommand;

    var cache = try Cache.init(ctx);
    defer cache.deinit();

    const arg = ctx.args[2];
    if (std.mem.eql(u8, arg, "size"))
        try cacheSize(ctx, &cache);
    if (std.mem.eql(u8, arg, "clean"))
        try cacheClean(ctx, &cache);
    if (std.mem.eql(u8, arg, "list") or
        std.mem.eql(u8, arg, "ls"))
        try cacheList(ctx, &cache);
}
