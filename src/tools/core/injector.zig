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

        self.injectIntoBuildZig() catch |err| {
            switch (err) {
                error.BuildFnNotFound => {
                    try self.printer.append("Build function not found in build.zig\n", .{}, .{ .color = 31 });
                },
                error.MissingInstallCall => {
                    try self.printer.append("No install call in build.zig\n", .{}, .{ .color = 31 });
                },
                error.InvalidInstallCall => {
                    try self.printer.append("Invalid install call in build.zig\n", .{}, .{ .color = 31 });
                },
                error.InvalidBuildSignature => {
                    try self.printer.append("Build parameter appears to be invalid\n", .{}, .{ .color = 31 });
                },
                else => {
                    try self.printer.append("Injecting into build.zig has failed.\n", .{}, .{ .color = 31 });
                    try self.printer.append("\nSUGGESTION:\n", .{}, .{ .color = 34 });
                    try self.printer.append(" - Delete build.zig\n $ zep init\n\n", .{}, .{});
                },
            }
        };
    }

    pub fn injectIntoBuildZig(self: *Injector) !void {
        try ZigInit.createZigProject(self.printer, self.allocator, "myproject", null);

        const path = "build.zig";
        var file = try Fs.openFile(path);
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, Constants.Default.mb * 2);
        defer self.allocator.free(content);

        const build_fn_start = "pub fn build(";
        const build_index = std.mem.indexOf(u8, content, build_fn_start) orelse return error.BuildFnNotFound;

        const after_build = content[build_index + build_fn_start.len ..];
        const param_end_index = std.mem.indexOfScalar(u8, after_build, ':') orelse return error.InvalidBuildSignature;

        const build_param = std.mem.trim(u8, after_build[0..param_end_index], " \t");

        const install_prefix_fmt = "{s}.installArtifact(";
        const install_prefix = try std.fmt.allocPrint(self.allocator, install_prefix_fmt, .{build_param});
        defer self.allocator.free(install_prefix);

        const install_index = std.mem.indexOf(u8, content, install_prefix) orelse return error.MissingInstallCall;

        const after_install = content[install_index + install_prefix.len ..];
        const artifact_end_index = std.mem.indexOfScalar(u8, after_install, ')') orelse return error.InvalidInstallCall;

        const artifact_name = std.mem.trim(u8, after_install[0..artifact_end_index], " \t");

        const inject_line_fmt =
            "    @import(\".zep/injector.zig\").injectExtraImports({s}, {s});\n";
        const inject_line = try std.fmt.allocPrint(self.allocator, inject_line_fmt, .{
            build_param,
            artifact_name,
        });
        defer self.allocator.free(inject_line);

        // Already injected?
        if (std.mem.indexOf(u8, content, inject_line) != null)
            return;

        const insert_before_fmt = "    {s}.installArtifact({s});";
        const insert_before = try std.fmt.allocPrint(self.allocator, insert_before_fmt, .{
            build_param,
            artifact_name,
        });
        defer self.allocator.free(insert_before);

        const insert_index = std.mem.indexOf(u8, content, insert_before) orelse return error.MissingInstallCall;

        try file.seekTo(0);
        try file.setEndPos(0);
        try file.writeAll(content[0..insert_index]);
        try file.writeAll(inject_line);
        try file.writeAll(content[insert_index..]);
    }
};
