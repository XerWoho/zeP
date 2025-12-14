const std = @import("std");

const c = @cImport({
    @cInclude("zstd.h");
});

pub fn compress(
    alloc: std.mem.Allocator,
    input: []const u8,
    level: i32,
) ![]u8 {
    const max = c.ZSTD_compressBound(input.len);
    var out = try alloc.alloc(u8, max);

    const size = c.ZSTD_compress(
        out.ptr,
        max,
        input.ptr,
        input.len,
        level,
    );

    if (c.ZSTD_isError(size) != 0)
        return error.ZstdCompressFailed;

    return out[0..size];
}

pub fn decompress(
    alloc: std.mem.Allocator,
    input: []const u8,
    original_size: usize,
) ![]u8 {
    const out = try alloc.alloc(u8, original_size);

    const size = c.ZSTD_decompress(
        out.ptr,
        original_size,
        input.ptr,
        input.len,
    );

    if (c.ZSTD_isError(size) != 0)
        return error.ZstdDecompressFailed;

    return out;
}
