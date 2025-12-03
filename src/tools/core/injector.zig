const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("manifest.zig");

const ZigInit = @import("zig_init.zig");

/// Injects package imports into build.zig.
/// package_name is required!
pub const Injector = struct {
    allocator: std.mem.Allocator,
    package_name: []const u8,
    printer: *Printer,

    pub fn init(allocator: std.mem.Allocator, package_name: []const u8, printer: *Printer) Injector {
        return Injector{ .allocator = allocator, .package_name = package_name, .printer = printer };
    }

    fn injector(self: *Injector, package_name: []const u8, path_name: []const u8) ![]u8 {
        const template =
            \\ 
            \\ // {name} MODULE 
            \\ const {name}Mod = b.createModule(.{ 
            \\ .root_source_file = b.path(".zep/{name}{path}"), 
            \\ }); 
            \\ exe.root_module.addImport("{name}", {name}Mod); 
            \\ // ---------- 
            \\
        ;

        const replaced_path = try std.mem.replaceOwned(u8, self.allocator, template, "{path}", path_name);
        defer self.allocator.free(replaced_path);

        const replaced_name = try std.mem.replaceOwned(u8, self.allocator, replaced_path, "{name}", package_name);
        return replaced_name;
    }

    pub fn initInjector(self: *Injector) !void {
        var lock_json = try Manifest.readManifest(Structs.ZepFiles.PackageLockStruct, self.allocator, Constants.Extras.package_files.lock);
        defer lock_json.deinit();

        var injected_packages = std.ArrayList([]u8).init(self.allocator);
        defer injected_packages.deinit();

        for (lock_json.value.packages) |package| {
            var split = std.mem.splitScalar(u8, package.name, '@');
            const package_name = split.first();
            const inj = try self.injector(package_name, package.root_file);
            try injected_packages.append(inj);
        }

        const total_packages = try injected_packages.toOwnedSlice();
        const injector_end = "}";

        if (Fs.existsFile(Constants.Extras.package_files.injector)) {
            try Fs.deleteFileIfExists(Constants.Extras.package_files.injector);
        }

        const injector_file = try Fs.openOrCreateFile(Constants.Extras.package_files.injector);
        defer injector_file.close();

        const injector_start = if (total_packages.len >= 1)
            "const std = @import(\"std\");\npub fn injectExtraImports(b: *std.Build, exe: *std.Build.Step.Compile) void {"
        else
            "const std = @import(\"std\");\npub fn injectExtraImports(_: *std.Build, _: *std.Build.Step.Compile) void {";

        _ = try injector_file.write(injector_start);
        for (total_packages) |p| {
            _ = try injector_file.write(p);
        }
        _ = try injector_file.write(injector_end);

        try self.injectIntoBuildZig();
    }

    pub fn injectIntoBuildZig(self: *Injector) !void {
        const child = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        });
        const zig_version = child.stdout[0 .. child.stdout.len - 1];
        try ZigInit.createZigProject(self.printer, self.allocator, "myproject", zig_version);

        const path = "build.zig";
        var file = try Fs.openFile(path);
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, Constants.Default.mb * 2);
        defer self.allocator.free(content);

        const inject_line = "    @import(\".zep/injector.zig\").injectExtraImports(b, exe);\n";
        const check_inject_line = "@import(\".zep/injector.zig\").injectExtraImports";

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const cleared_content = std.mem.trimLeft(u8, line, " ");
            if (std.mem.startsWith(u8, cleared_content, check_inject_line))
                return;
        }
        const insert_before = "    b.installArtifact(exe);";
        const index = std.mem.indexOf(u8, content, insert_before) orelse return error.MissingInstallCall;

        try file.seekTo(0);
        try file.setEndPos(0);
        _ = try file.writeAll(content[0..index]);
        _ = try file.writeAll(inject_line);
        _ = try file.writeAll(content[index..]);
    }
};
