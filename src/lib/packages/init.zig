const std = @import("std");

const Constants = @import("constants");
const Structs = @import("structs");

const Fs = @import("io").Fs;
const Json = @import("core").Json.Json;
const Printer = @import("cli").Printer;

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

fn promptInput(stdin: anytype, prompt: []const u8, required: bool, printer: *Printer, allocator: std.mem.Allocator) ![]const u8 {
    try printer.append("{s}", .{prompt}, .{});
    var line: []const u8 = "";

    while (true) {
        var read_line = try stdin.readUntilDelimiterAlloc(allocator, '\n', Constants.Default.kb);
        if (required and read_line.len <= 1) {
            allocator.free(read_line);
            try printer.print();
            continue;
        }

        line = read_line[0 .. read_line.len - 1];
        break;
    }

    try printer.append("{s}\n", .{line}, .{});
    return line;
}

pub const Init = struct {
    allocator: std.mem.Allocator,
    json: Json,
    printer: *Printer,

    zig_version: []const u8 = "0.14.0",
    name: []const u8 = "",
    description: []const u8 = "",
    license: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, printer: *Printer, default: bool) !Init {
        const json = try Json.init(allocator);
        if (default) {
            return Init{
                .allocator = allocator,
                .json = json,
                .printer = printer,
            };
        }

        const child = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        });
        const zig_version = child.stdout[0 .. child.stdout.len - 1];

        try printer.append("--- INITTING ZEP MODE ---\n\n", .{}, .{ .color = 34 });
        const stdin = std.io.getStdIn().reader();

        const name = try promptInput(stdin, "> Name: ", true, printer, allocator);
        const description = try promptInput(stdin, "> Description: ", true, printer, allocator);
        const license = try promptInput(stdin, "> License: ", true, printer, allocator);

        return Init{
            .allocator = allocator,
            .json = json,
            .zig_version = zig_version,
            .printer = printer,

            .license = license,
            .name = name,
            .description = description,
        };
    }

    pub fn commitInit(self: *Init) !void {
        try self.printer.append("Initing zep project...\n", .{}, .{});

        try self.createFolders();
        try self.createFiles();

        // auto init zig
        try self.createZigProject();

        try self.printer.append("Finished initting!\n", .{}, .{ .color = 32 });
    }

    fn createFolders(_: *Init) !void {
        const cwd = std.fs.cwd();
        _ = cwd.makeDir(Constants.Extras.package_files.zep_folder) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn createFiles(self: *Init) !void {
        var pkg = Structs.ZepFiles.PackageJsonStruct{
            .build = Structs.ZepFiles.BuildPackageJsonStruct{},
        };
        pkg.zig_version = self.zig_version;

        const lock = Structs.ZepFiles.PackageLockStruct{ .root = pkg };

        if (!Fs.existsFile(Constants.Extras.package_files.manifest)) {
            try self.json.writePretty(Constants.Extras.package_files.manifest, pkg);
        }

        if (!Fs.existsFile(Constants.Extras.package_files.lock)) {
            try self.json.writePretty(Constants.Extras.package_files.lock, lock);
        }
    }

    fn createZigProject(self: *Init) !void {
        const zig_main_path = "src/main.zig";
        const zig_build_path = "build.zig";
        const zig_build_zon_path = "build.zig.zon";

        try self.printer.append("Initting Zig project...\n", .{}, .{});

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
        const zb_replace_name = try std.mem.replaceOwned(u8, self.allocator, zig_build, "{name}", self.name);
        defer self.allocator.free(zb_replace_name);

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
        const fingerprint_struct = Fingerprint.generate(self.name);
        const fingerprint = try std.fmt.allocPrint(self.allocator, "0x{x}", .{fingerprint_struct.int()});
        defer self.allocator.free(fingerprint);

        const zbz_replace_name = try std.mem.replaceOwned(u8, self.allocator, zig_build_zon, "{name}", self.name);
        defer self.allocator.free(zbz_replace_name);

        const zbz_replace_fingerprint = try std.mem.replaceOwned(u8, self.allocator, zbz_replace_name, "{fingerprint}", fingerprint);
        defer self.allocator.free(zbz_replace_fingerprint);

        const zbz_replace_zig_version = try std.mem.replaceOwned(u8, self.allocator, zbz_replace_fingerprint, "{zig_version}", self.zig_version);
        defer self.allocator.free(zbz_replace_zig_version);

        if (!Fs.existsFile(zig_build_zon_path)) {
            const f = try Fs.openOrCreateFile(zig_build_zon_path);
            _ = try f.write(zbz_replace_zig_version);
        }
    }
};
