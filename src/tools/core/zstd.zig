const std = @import("std");
const Logger = @import("logger");

const c = @cImport({
    @cInclude("zstd.h");
});

pub fn compress(
    alloc: std.mem.Allocator,
    input: []const u8,
    level: i32,
) ![]u8 {
    const logger = Logger.get();
    try logger.infof("ZSTD: Compressing data of length {d} with level {d}", .{ input.len, level }, @src());

    const max = c.ZSTD_compressBound(input.len);
    var out = try alloc.alloc(u8, max);

    const size = c.ZSTD_compress(
        out.ptr,
        max,
        input.ptr,
        input.len,
        level,
    );

    if (c.ZSTD_isError(size) != 0) {
        try logger.info("ZSTD: Compression failed!", @src());
        return error.ZstdCompressFailed;
    }

    try logger.infof("ZSTD: Compression succeeded, output size {d}", .{size}, @src());
    return out[0..size];
}

pub fn decompress(
    alloc: std.mem.Allocator,
    input: []const u8,
    original_size: usize,
) ![]u8 {
    const logger = Logger.get();
    try logger.infof("ZSTD: Decompressing data of length {d} to original size {d}", .{ input.len, original_size }, @src());

    const out = try alloc.alloc(u8, original_size);

    const size = c.ZSTD_decompress(
        out.ptr,
        original_size,
        input.ptr,
        input.len,
    );

    if (c.ZSTD_isError(size) != 0) {
        try logger.info("ZSTD: Decompression failed!", @src());
        return error.ZstdDecompressFailed;
    }

    try logger.infof("ZSTD: Decompression succeeded, output size {d}", .{size}, @src());
    return out;
}
