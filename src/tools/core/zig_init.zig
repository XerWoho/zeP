const std = @import("std");

const Logger = @import("logger");
const Constants = @import("constants");

const Printer = @import("cli").Printer;
const Fs = @import("io").Fs;

pub const Fingerprint = packed struct(u64) {
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

pub fn createZigProject(printer: *Printer, allocator: std.mem.Allocator, name: []const u8, default_zig_version: ?[]const u8) !void {
    const logger = Logger.get();

    const zig_main_path = "src/main.zig";
    const zig_build_path = "build.zig";
    const zig_build_zon_path = "build.zig.zon";

    if (Fs.existsFile(zig_main_path) and Fs.existsFile(zig_build_path) and Fs.existsFile(zig_build_zon_path)) {
        try logger.info("Zig project already initialized, skipping.", @src());
        return;
    }

    var zig_version: []const u8 = default_zig_version orelse "0.14.0";

    blk: {
        if (default_zig_version != null) break :blk;

        const child = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch |err| {
            try printer.append(
                "Zig is not installed!\nDefaulting to {s}!\n\n",
                .{zig_version},
                .{
                    .color = .red,
                    .verbosity = 0,
                },
            );
            try logger.warnf("Zig not detected, defaulting to version {s}, err={}", .{ zig_version, err }, @src());
            break :blk;
        };

        zig_version = child.stdout[0 .. child.stdout.len - 1];
        try logger.infof("Detected Zig version: {s}", .{zig_version}, @src());
    }

    try printer.append("Initing Zig project...\n", .{}, .{});
    try logger.info("Initializing Zig project structure...", @src());

    const zig_main =
        \\
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\  std.debug.print("Auto init, using zep.\n\n", .{});
        \\}
    ;
    if (!Fs.existsFile(zig_main_path)) {
        const f = try Fs.openOrCreateFile(zig_main_path);
        _ = try f.write(zig_main);
        try logger.infof("Created {s}", .{zig_main_path}, @src());
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
        try logger.infof("Created {s}", .{zig_build_path}, @src());
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
    var buf: [32]u8 = undefined;
    const fingerprint = try std.fmt.bufPrint(&buf, "0x{x}", .{fingerprint_struct.int()});

    const zbz_replace_name = try std.mem.replaceOwned(u8, allocator, zig_build_zon, "{name}", name);
    defer allocator.free(zbz_replace_name);

    const zbz_replace_fingerprint = try std.mem.replaceOwned(u8, allocator, zbz_replace_name, "{fingerprint}", fingerprint);
    defer allocator.free(zbz_replace_fingerprint);

    const zbz_replace_zig_version = try std.mem.replaceOwned(u8, allocator, zbz_replace_fingerprint, "{zig_version}", zig_version);
    defer allocator.free(zbz_replace_zig_version);

    if (!Fs.existsFile(zig_build_zon_path)) {
        const f = try Fs.openOrCreateFile(zig_build_zon_path);
        _ = try f.write(zbz_replace_zig_version);
        try logger.infof("Created {s}", .{zig_build_zon_path}, @src());
    }

    try logger.info("Zig project initialization completed.", @src());
}
