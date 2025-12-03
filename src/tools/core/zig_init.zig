const std = @import("std");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

const Constants = @import("constants");

const Fingerprint = packed struct(u64) {
    id: u32,
    checksum: u32,

    pub fn generate(name: []const u8) Fingerprint {
        return .{
            .id = std.crypto.random.intRangeLessThan(u32, 1, 0xffffffff),
            .checksum = std.hash.Crc32.hash(name),
        };
    }

    pub fn validate(n: Fingerprint, name: []const u8) bool {
        switch (n.id) {
            0x00000000, 0xffffffff => return false,
            else => return std.hash.Crc32.hash(name) == n.checksum,
        }
    }

    pub fn int(n: Fingerprint) u64 {
        return @bitCast(n);
    }
};

pub fn createZigProject(printer: *Printer, allocator: std.mem.Allocator, name: []const u8, zig_version: []const u8) !void {
    const zig_main_path = "src/main.zig";
    const zig_build_path = "build.zig";
    const zig_build_zon_path = "build.zig.zon";

    try printer.append("Initting Zig project...\n", .{}, .{});

    const zig_main =
        \\
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\  std.debug.print("Auto init, using zeP.", .{});
        \\}
    ;
    if (!Fs.existsFile(zig_main_path)) {
        const f = try Fs.openOrCreateFile(zig_main_path);
        _ = try f.write(zig_main);
    }

    const zig_build =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "{name}",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
    ;
    const zb_replace_name = try std.mem.replaceOwned(u8, allocator, zig_build, "{name}", name);
    defer allocator.free(zb_replace_name);

    if (!Fs.existsFile(zig_build_path)) {
        const f = try Fs.openOrCreateFile(zig_build_path);
        _ = try f.write(zb_replace_name);
    }

    const zig_build_zon =
        \\.{
        \\    .name = .{name},
        \\    .version = "0.0.1",
        \\    .fingerprint = {fingerprint},
        \\    .minimum_zig_version = "{zig_version}",
        \\    .dependencies = .{},
        \\    .paths = .{""},
        \\}
        \\
    ;
    const fingerprint_struct = Fingerprint.generate(name);
    const fingerprint = try std.fmt.allocPrint(allocator, "0x{x}", .{fingerprint_struct.int()});
    defer allocator.free(fingerprint);

    const zbz_replace_name = try std.mem.replaceOwned(u8, allocator, zig_build_zon, "{name}", name);
    defer allocator.free(zbz_replace_name);

    const zbz_replace_fingerprint = try std.mem.replaceOwned(u8, allocator, zbz_replace_name, "{fingerprint}", fingerprint);
    defer allocator.free(zbz_replace_fingerprint);

    const zbz_replace_zig_version = try std.mem.replaceOwned(u8, allocator, zbz_replace_fingerprint, "{zig_version}", zig_version);
    defer allocator.free(zbz_replace_zig_version);

    if (!Fs.existsFile(zig_build_zon_path)) {
        const f = try Fs.openOrCreateFile(zig_build_zon_path);
        _ = try f.write(zbz_replace_zig_version);
    }
}
