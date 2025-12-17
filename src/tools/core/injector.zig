const std = @import("std");

const Structs = @import("structs");
const Constants = @import("constants");
const Logger = @import("logger");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Manifest = @import("manifest.zig").Manifest;

const ZigInit = @import("zig_init.zig");

fn contains(haystack: []const u8, needle: []const u8) bool {
    const haystack_len = haystack.len;
    const needle_len = needle.len;
    if (needle_len == 0) return false;
    if (haystack_len < needle_len) return false;
    if (haystack_len == needle_len) return std.mem.eql(u8, haystack, needle);

    var i: usize = 0;
    while (i + needle_len <= haystack_len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i .. i + needle_len], needle)) return true;
    }
    return false;
}

fn isInArray(haystack: [][]const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn indexOf(haystack: [][]const u8, needle: []const u8) ?usize {
    for (haystack, 0..) |item, i| {
        if (std.mem.eql(u8, item, needle)) return i;
    }
    return null;
}

/// Injects package imports into build.zig.
/// package_name is required!
pub const Injector = struct {
    allocator: std.mem.Allocator,
    printer: *Printer,
    manifest: *Manifest,
    force_inject: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        manifest: *Manifest,
        force_inject: bool,
    ) !Injector {
        const logger = Logger.get();
        try logger.debug("Injector: init", @src());

        return Injector{
            .allocator = allocator,
            .printer = printer,
            .manifest = manifest,
            .force_inject = force_inject,
        };
    }

    fn injector(self: *Injector, package_name: []const u8, path_name: []const u8) ![]u8 {
        const logger = Logger.get();
        try logger.debugf("injector: creating template for package={s} path={s}", .{ package_name, path_name }, @src());

        const template = try self.renderInjector(package_name, path_name);
        try logger.debugf("injector: template replaced for package={s}", .{package_name}, @src());

        return template;
    }

    fn renderInjector(
        self: *Injector,
        pkg: []const u8,
        path: []const u8,
    ) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\ // {s} MODULE
            \\ const {s}Mod = b.createModule(.{{
            \\     .root_source_file = b.path(".zep/{s}{s}"),
            \\ }});
            \\ exe.addImport("{s}", {s}Mod);
            \\ // ----------
            \\
        , .{ pkg, pkg, pkg, path, pkg, pkg });
    }

    const inject_method = enum {
        nothing,
        add_include,
        add_exclude,
    };

    fn shouldInject(
        self: *Injector,
        module: []const u8,
        state: *Structs.Manifests.InjectorManifest,
    ) !inject_method {
        if (!self.force_inject) {
            if (isInArray(state.excluded_modules, module) or
                isInArray(state.included_modules, module))
                return inject_method.nothing;
        }

        var stdin_buf: [100]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
        const stdin = &stdin_reader.interface;
        const prompt = try std.fmt.allocPrint(
            self.allocator,
            "Import packages for \"{s}\"? (Y/n) ",
            .{module},
        );
        defer self.allocator.free(prompt);

        const ans = try Prompt.input(
            self.allocator,
            self.printer,
            stdin,
            prompt,
            .{},
        );
        const answer_yes = !(ans.len > 0 and (ans[0] == 'n' or ans[0] == 'N'));
        const answer_no = !answer_yes;
        if (isInArray(state.included_modules, module)) {
            if (answer_yes) return inject_method.nothing;
            if (answer_no) return inject_method.add_exclude;
        } else if (isInArray(state.excluded_modules, module)) {
            if (answer_yes) return inject_method.add_include;
            if (answer_no) return inject_method.nothing;
        } else {
            if (answer_yes) return inject_method.add_include;
            if (answer_no) return inject_method.add_exclude;
        }
        return inject_method.nothing;
    }

    pub fn initInjector(self: *Injector) !void {
        const logger = Logger.get();
        try logger.debug("initInjector: start", @src());

        var lock = try self.manifest.readManifest(
            Structs.ZepFiles.PackageLockStruct,
            Constants.Extras.package_files.lock,
        );
        defer lock.deinit();

        var snippets = try std.ArrayList([]u8).initCapacity(self.allocator, 20);
        defer snippets.deinit(self.allocator);

        for (lock.value.packages) |pkg| {
            var split = std.mem.splitScalar(u8, pkg.name, '@');
            const name = split.first();
            try snippets.append(self.allocator, try self.renderInjector(name, pkg.root_file));
        }

        try Fs.deleteFileIfExists(Constants.Extras.package_files.injector);

        var file = try Fs.openOrCreateFile(Constants.Extras.package_files.injector);
        defer file.close();

        const header =
            if (snippets.items.len > 0)
                "const std = @import(\"std\");\npub fn imp(b: *std.Build, exe: *std.Build.Module) void {\n"
            else
                "const std = @import(\"std\");\npub fn imp(_: *std.Build, _: *std.Build.Module) void {\n";

        _ = try file.write(header);
        for (snippets.items) |s| _ = try file.write(s);
        _ = try file.write("}\n");

        try self.injectIntoBuildZig();
    }

    fn findBuildParam(_: *Injector, content: []const u8) ![]const u8 {
        const start = std.mem.indexOf(u8, content, "pub fn build(") orelse
            return error.BuildFnNotFound;

        const after = content[start + "pub fn build(".len ..];
        const end = std.mem.indexOfScalar(u8, after, ':') orelse
            return error.InvalidBuildSignature;

        return std.mem.trim(u8, after[0..end], " \t");
    }

    fn importModule(
        self: *Injector,
        injector_manifest: *Structs.Manifests.InjectorManifest,
        new_excluded_modules: *std.ArrayList([]const u8),
        new_included_modules: *std.ArrayList([]const u8),
        module_name: []const u8,
    ) !inject_method {
        const modify_injection = try self.shouldInject(module_name, injector_manifest);
        switch (modify_injection) {
            inject_method.add_include => {
                try new_included_modules.append(self.allocator, module_name);
                const idx = indexOf(new_excluded_modules.items, module_name);
                if (idx) |i| {
                    _ = new_excluded_modules.swapRemove(i);
                }
            },
            inject_method.add_exclude => {
                try new_excluded_modules.append(self.allocator, module_name);
                const idx = indexOf(new_included_modules.items, module_name);
                if (idx) |i| {
                    _ = new_included_modules.swapRemove(i);
                }
            },
            inject_method.nothing => {},
        }
        return modify_injection;
    }

    fn maybeInject(
        self: *Injector,
        injector_manifest: *Structs.Manifests.InjectorManifest,
        new_excluded: *std.ArrayList([]const u8),
        new_included: *std.ArrayList([]const u8),
        included_modules: [][]const u8,
        build_param: []const u8,
        module_name: []const u8,
        new_content: *std.ArrayList([]const u8),
    ) !void {
        const imported = try self.importModule(
            injector_manifest,
            new_excluded,
            new_included,
            module_name,
        );

        const fmt = try std.fmt.allocPrint(
            self.allocator,
            "    __zepinj__.imp({s}, {s});\n",
            .{ build_param, module_name },
        );

        switch (imported) {
            .add_include => try new_content.append(self.allocator, fmt),
            .add_exclude => {},
            .nothing => {
                if (isInArray(included_modules, module_name)) {
                    try new_content.append(self.allocator, fmt);
                }
            },
        }
    }

    fn parseModuleDefinition(
        line: []const u8,
        install_prefix: []const u8,
        excluded_modules: [][]const u8,
        force_inject: bool,
    ) ?[]const u8 {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (!contains(trimmed, install_prefix)) return null;

        var eq_split = std.mem.splitAny(u8, line, "=");
        const lhs = std.mem.trim(u8, eq_split.first(), " ");

        var parts = std.mem.splitAny(u8, lhs, " ");
        _ = parts.next(); // var/const
        const module_name = parts.next() orelse return null;

        if (!force_inject and isInArray(excluded_modules, module_name)) {
            return null;
        }

        return module_name;
    }

    pub fn injectIntoBuildZig(self: *Injector) !void {
        const logger = Logger.get();
        try logger.debug("injectIntoBuildZig: start", @src());

        try ZigInit.createZigProject(self.printer, self.allocator, "myproject", null);
        try logger.debug("injectIntoBuildZig: created Zig project", @src());

        const path = "build.zig";
        try logger.debug("injectIntoBuildZig: opening build.zig", @src());
        var file = try Fs.openFile(path);
        defer file.close();

        try logger.debug("injectIntoBuildZig: read build.zig content", @src());
        const content = try file.readToEndAlloc(self.allocator, Constants.Default.mb * 2);
        defer self.allocator.free(content);

        try logger.debug("injectIntoBuildZig: finding build parameter", @src());
        const build_param = try self.findBuildParam(content);
        try logger.debugf("injectIntoBuildZig: build parameter={s}", .{build_param}, @src());

        var injector_manifest = try self.manifest.readManifest(Structs.Manifests.InjectorManifest, Constants.Extras.package_files.injector_manifest);
        defer injector_manifest.deinit();
        const included_modules = injector_manifest.value.included_modules;
        const excluded_modules = injector_manifest.value.excluded_modules;

        display_module_blk: {
            var stdin_buf: [100]u8 = undefined;
            var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
            const stdin = &stdin_reader.interface;

            try self.printer.append("Modules currently imported:\n", .{}, .{ .color = .blue, .weight = .bold });
            for (included_modules) |mod| {
                try self.printer.append("  + {s}\n", .{mod}, .{});
            }
            try self.printer.append("\n", .{}, .{});

            const ans = try Prompt.input(
                self.allocator,
                self.printer,
                stdin,
                "Keep these imports? (Y/n) ",
                .{},
            );
            const answer_yes = !(ans.len > 0 and (ans[0] == 'n' or ans[0] == 'N'));
            if (answer_yes) {
                try logger.debug("injectIntoBuildZig: current imports accepted - exiting", @src());
                try self.printer.append("Done.\n", .{}, .{});
                return;
            } else {
                try self.printer.append("\n", .{}, .{});
            }

            break :display_module_blk;
        }

        var current_module: ?[]const u8 = null;
        var new_content = try std.ArrayList([]const u8).initCapacity(self.allocator, 150);
        defer new_content.deinit(self.allocator);

        var file_writer = try std.ArrayList([]const u8).initCapacity(self.allocator, 150);
        defer file_writer.deinit(self.allocator);

        //
        //              This is what we find
        //             vvvvvvvvvvvvvvvvvvvvv
        // const mod = builder.createModule(.{
        //     .root_source_file = builder.path("..."),
        // });
        const install_prefix_fmt = "{s}.createModule(";
        var install_prefix_buf: [64]u8 = undefined;
        const install_prefix = try std.fmt.bufPrint(&install_prefix_buf, install_prefix_fmt, .{build_param});

        var split_data = std.mem.splitAny(u8, content, "\n");

        try logger.debug("injectIntoBuildZig: reading injector.json", @src());
        var new_included_modules = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        defer new_included_modules.deinit(self.allocator);
        try new_included_modules.appendSlice(self.allocator, included_modules);

        var new_excluded_modules = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        defer new_excluded_modules.deinit(self.allocator);
        try new_excluded_modules.appendSlice(self.allocator, excluded_modules);

        try logger.debug("injectIntoBuildZig: iterating over lines", @src());
        while (split_data.next()) |line| {
            if (contains(line, "__zepinj__")) continue;
            if (contains(line, "@import(\".zep/inject\")")) continue;

            try new_content.append(self.allocator, line);
            try new_content.append(self.allocator, "\n");

            // Finish pending multi-line module
            if (current_module) |module| {
                if (!contains(line, ";")) continue;

                try self.maybeInject(
                    &injector_manifest.value,
                    &new_excluded_modules,
                    &new_included_modules,
                    included_modules,
                    build_param,
                    module,
                    &new_content,
                );

                current_module = null;
                continue;
            }

            const module = parseModuleDefinition(
                line,
                install_prefix,
                excluded_modules,
                self.force_inject,
            ) orelse continue;

            current_module = module;

            if (!contains(line, ";")) continue;

            try self.maybeInject(
                &injector_manifest.value,
                &new_excluded_modules,
                &new_included_modules,
                included_modules,
                build_param,
                module,
                &new_content,
            );

            current_module = null;
        }

        verify_module_blk: {
            var stdin_buf: [100]u8 = undefined;
            var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
            const stdin = &stdin_reader.interface;

            const module_count: u8 = @intCast(new_excluded_modules.items.len + new_included_modules.items.len);
            self.printer.pop(module_count * 2); // pop the prompt, aswell as the answer
            try self.printer.clearLine(module_count);

            try self.printer.append("\nzeP import plan:\n\n", .{}, .{ .color = .blue, .weight = .bold });

            try self.printer.append("Will import:\n", .{}, .{});
            var exc_diff = false;
            for (excluded_modules) |mod| {
                if (!isInArray(new_excluded_modules.items, mod)) {
                    exc_diff = true;
                    try self.printer.append("  + {s}\n", .{mod}, .{});
                }
            }
            if (!exc_diff) {
                try self.printer.append("  # none (new)\n", .{}, .{});
            }

            try self.printer.append("\nWill remove:\n", .{}, .{});
            var inc_diff = false;
            for (included_modules) |mod| {
                if (!isInArray(new_included_modules.items, mod)) {
                    inc_diff = true;
                    try self.printer.append("  - {s}\n", .{mod}, .{});
                }
            }
            if (!inc_diff) {
                try self.printer.append("  # none (new)\n", .{}, .{});
            }
            try self.printer.append("\n", .{}, .{});

            if (inc_diff or exc_diff) {
                const ans = try Prompt.input(
                    self.allocator,
                    self.printer,
                    stdin,
                    "Apply changes? (Y/n) ",
                    .{},
                );
                const answer_yes = !(ans.len > 0 and (ans[0] == 'n' or ans[0] == 'N'));
                if (!answer_yes) {
                    try self.printer.append("Ok.\n", .{}, .{});
                    try logger.debug("injectIntoBuildZig: changes rejected - exiting", @src());
                    return;
                }
            } else {
                try self.printer.append("No changes made.\n", .{}, .{});
                try logger.debug("injectIntoBuildZig: no changes made - exiting", @src());
                return;
            }

            break :verify_module_blk;
        }

        try logger.debug("injectIntoBuildZig: writing to manifest", @src());
        try self.manifest.writeManifest(
            Structs.Manifests.InjectorManifest,
            Constants.Extras.package_files.injector_manifest,
            Structs.Manifests.InjectorManifest{
                .included_modules = new_included_modules.items,
                .excluded_modules = new_excluded_modules.items,
            },
        );

        try logger.debug("injectIntoBuildZig: writing to build.zig", @src());
        try file.seekTo(0);
        try file.setEndPos(0);
        const import_injector = "const __zepinj__ = @import(\".zep/injector.zig\");\n";
        _ = try file.write(import_injector);
        for (new_content.items, 0..) |c, i| {
            if (i == new_content.items.len - 1) {
                if (std.mem.eql(u8, c, "\n")) continue;
            }
            _ = try file.write(c);
        }
        try self.printer.append("Done.\n", .{}, .{});
        try logger.info("injectIntoBuildZig: injection complete", @src());
    }
};
