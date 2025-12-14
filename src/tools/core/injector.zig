const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");
const Logger = @import("logger");

const Fs = @import("io").Fs;
const Printer = @import("cli").Printer;
const Manifest = @import("manifest.zig").Manifest;

const ZigInit = @import("zig_init.zig");

/// Injects package imports into build.zig.
/// package_name is required!
pub const Injector = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    manifest: *Manifest,
    package_name: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        manifest: *Manifest,
        package_name: []const u8,
    ) !Injector {
        const logger = Logger.get();
        try logger.debug("Injector: init", @src());

        return Injector{
            .allocator = allocator,
            .printer = printer,
            .manifest = manifest,
            .package_name = package_name,
        };
    }

    fn injector(self: *Injector, package_name: []const u8, path_name: []const u8) ![]u8 {
        const logger = Logger.get();
        try logger.debugf("injector: creating template for package={s} path={s}", .{ package_name, path_name }, @src());

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
        try logger.debugf("injector: template replaced for package={s}", .{package_name}, @src());

        return replaced_name;
    }

    pub fn initInjector(self: *Injector) !void {
        const logger = Logger.get();
        try logger.debug("initInjector: start", @src());

        var lock_json = try self.manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );
        defer lock_json.deinit();

        var injected_packages = try std.ArrayList([]u8).initCapacity(self.allocator, 10);
        defer injected_packages.deinit(self.allocator);

        try logger.debug("initInjector: iterating over locked packages", @src());
        for (lock_json.value.packages) |package| {
            var split = std.mem.splitScalar(u8, package.name, '@');
            const package_name = split.first();
            const inj = try self.injector(package_name, package.root_file);
            try injected_packages.append(self.allocator, inj);
            try logger.debugf("initInjector: injected package={s}", .{package_name}, @src());
        }

        const total_packages = try injected_packages.toOwnedSlice(self.allocator);
        const injector_end = "}";

        if (Fs.existsFile(Constants.Extras.package_files.injector)) {
            try logger.debugf("initInjector: removing existing injector file {s}", .{Constants.Extras.package_files.injector}, @src());
            try Fs.deleteFileIfExists(Constants.Extras.package_files.injector);
        }

        const injector_file = try Fs.openOrCreateFile(Constants.Extras.package_files.injector);
        defer injector_file.close();

        const injector_start = if (total_packages.len >= 1)
            "const std = @import(\"std\");\npub fn injectExtraImports(b: *std.Build, exe: *std.Build.Step.Compile) void {"
        else
            "const std = @import(\"std\");\npub fn injectExtraImports(_: *std.Build, _: *std.Build.Step.Compile) void {";

        _ = try injector_file.write(injector_start);
        try logger.debug("initInjector: writing injector start", @src());

        for (total_packages) |p| {
            _ = try injector_file.write(p);
        }
        try logger.debug("initInjector: writing injected packages", @src());

        _ = try injector_file.write(injector_end);
        try logger.debug("initInjector: finished writing injector file", @src());

        self.injectIntoBuildZig() catch |err| {
            const printer = self.printer;
            switch (err) {
                error.BuildFnNotFound => {
                    try logger.warn("injectIntoBuildZig: Build function not found", @src());
                    try printer.append("Build function not found in build.zig\n", .{}, .{ .color = .red });
                },
                error.MissingInstallCall => {
                    try logger.warn("injectIntoBuildZig: Missing install call", @src());
                    try printer.append("No install call in build.zig\n", .{}, .{ .color = .red });
                },
                error.InvalidInstallCall => {
                    try logger.warn("injectIntoBuildZig: Invalid install call", @src());
                    try printer.append("Invalid install call in build.zig\n", .{}, .{ .color = .red });
                },
                error.InvalidBuildSignature => {
                    try logger.warn("injectIntoBuildZig: Invalid build signature", @src());
                    try printer.append("Build parameter appears to be invalid\n", .{}, .{ .color = .red });
                },
                else => {
                    try logger.err("injectIntoBuildZig: unknown error", @src());
                    try printer.append("Injecting into build.zig has failed.\n", .{}, .{ .color = .red });
                    try printer.append("\nSUGGESTION:\n", .{}, .{ .color = .blue });
                    try printer.append(" - Delete build.zig\n $ zep init\n\n", .{}, .{});
                },
            }
        };

        try logger.debug("initInjector: end", @src());
    }

    pub fn injectIntoBuildZig(self: *Injector) !void {
        const logger = Logger.get();
        try logger.debug("injectIntoBuildZig: start", @src());

        try ZigInit.createZigProject(self.printer, self.allocator, "myproject", null);
        try logger.debug("injectIntoBuildZig: created Zig project", @src());

        const path = "build.zig";
        var file = try Fs.openFile(path);
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, Constants.Default.mb * 2);
        defer self.allocator.free(content);
        try logger.debug("injectIntoBuildZig: read build.zig content", @src());

        const build_fn_start = "pub fn build(";
        const build_index = std.mem.indexOf(u8, content, build_fn_start) orelse {
            try logger.warn("injectIntoBuildZig: build function not found", @src());
            return error.BuildFnNotFound;
        };

        const after_build = content[build_index + build_fn_start.len ..];
        const param_end_index = std.mem.indexOfScalar(u8, after_build, ':') orelse {
            try logger.warn("injectIntoBuildZig: invalid build signature", @src());
            return error.InvalidBuildSignature;
        };

        const build_param = std.mem.trim(u8, after_build[0..param_end_index], " \t");
        try logger.debugf("injectIntoBuildZig: build parameter={s}", .{build_param}, @src());

        const install_prefix_fmt = "{s}.installArtifact(";
        var install_prefix_buf: [64]u8 = undefined;
        const install_prefix = try std.fmt.bufPrint(&install_prefix_buf, install_prefix_fmt, .{build_param});

        const install_index = std.mem.indexOf(u8, content, install_prefix) orelse {
            try logger.warn("injectIntoBuildZig: missing install call", @src());
            return error.MissingInstallCall;
        };

        const after_install = content[install_index + install_prefix.len ..];
        const artifact_end_index = std.mem.indexOfScalar(u8, after_install, ')') orelse {
            try logger.warn("injectIntoBuildZig: invalid install call", @src());
            return error.InvalidInstallCall;
        };

        const artifact_name = std.mem.trim(u8, after_install[0..artifact_end_index], " \t");
        try logger.debugf("injectIntoBuildZig: artifact name={s}", .{artifact_name}, @src());

        var inject_line_buf: [128]u8 = undefined;
        const inject_line_fmt = "    @import(\".zep/injector.zig\").injectExtraImports({s}, {s});\n";
        const inject_line = try std.fmt.bufPrint(&inject_line_buf, inject_line_fmt, .{ build_param, artifact_name });

        var check_inject_line_buf: [128]u8 = undefined;
        const check_inject_line_fmt = "@import(\".zep/injector.zig\").injectExtraImports({s}, {s});";
        const check_inject_line = try std.fmt.bufPrint(&check_inject_line_buf, check_inject_line_fmt, .{ build_param, artifact_name });

        if (std.mem.indexOf(u8, content, check_inject_line) != null) {
            try logger.debug("injectIntoBuildZig: injection already present, skipping", @src());
            return;
        }

        const insert_before_fmt = "    {s}.installArtifact({s});";
        var insert_before_buf: [64]u8 = undefined;
        const insert_before = try std.fmt.bufPrint(&insert_before_buf, insert_before_fmt, .{ build_param, artifact_name });

        const insert_index = std.mem.indexOf(u8, content, insert_before) orelse {
            try logger.warn("injectIntoBuildZig: install call not found for insertion", @src());
            return error.MissingInstallCall;
        };

        try file.seekTo(0);
        try file.setEndPos(0);
        try file.writeAll(content[0..insert_index]);
        try file.writeAll(inject_line);
        try file.writeAll(content[insert_index..]);

        try logger.info("injectIntoBuildZig: injection complete", @src());
    }
};
