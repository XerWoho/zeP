const std = @import("std");

pub const Injector = @This();

const Structs = @import("structs");
const Constants = @import("constants");
const Logger = @import("logger");

const Fs = @import("io").Fs;
const Prompt = @import("cli").Prompt;
const Printer = @import("cli").Printer;
const Manifest = @import("manifest.zig");

const ZigInit = @import("zig_init.zig");
const Zon = @import("zon");

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

allocator: std.mem.Allocator,
manifest: Manifest,
printer: *Printer,

pub fn init(
    allocator: std.mem.Allocator,
    manifest: Manifest,
    printer: *Printer,
) Injector {
    return Injector{
        .allocator = allocator,
        .manifest = manifest,
        .printer = printer,
    };
}

fn renderInjector(
    self: *Injector,
    pkg: []const u8,
) ![]u8 {
    var copy_pkg = try self.allocator.dupe(u8, pkg);
    defer self.allocator.free(copy_pkg);

    if (std.mem.endsWith(u8, copy_pkg, ".zig")) {
        copy_pkg = copy_pkg[0 .. copy_pkg.len - 4]; // remove ".zig"
    }
    std.mem.replaceScalar(
        u8,
        copy_pkg,
        '-',
        '_',
    );

    return std.fmt.allocPrint(self.allocator,
        \\ // {s} MODULE
        \\ const {s}_dep = b.dependency("{s}", .{{}});
        \\ exe.addImport("{s}", {s}_dep.module("{s}"));
        \\ // ----------
        \\
    , .{ pkg, copy_pkg, copy_pkg, copy_pkg, copy_pkg, copy_pkg });
}

const inject_method = enum {
    nothing,
    add_include,
    add_exclude,
};

fn shouldInject(
    self: *Injector,
    module: []const u8,
    excluded_modules: [][]const u8,
    included_modules: [][]const u8,
    force_inject: bool,
) !inject_method {
    if (!force_inject) {
        if (isInArray(excluded_modules, module) or
            isInArray(included_modules, module))
            return inject_method.nothing;
    }

    const prompt = try std.fmt.allocPrint(
        self.allocator,
        "Import packages for \"{s}\"? (Y/n) ",
        .{module},
    );
    defer self.allocator.free(prompt);

    const answer = try Prompt.input(
        self.allocator,
        self.printer,
        prompt,
        .{},
    );
    const answer_yes = !(answer.len > 0 and (answer[0] == 'n' or answer[0] == 'N'));
    const answer_no = !answer_yes;
    if (isInArray(included_modules, module)) {
        if (answer_yes) return inject_method.nothing;
        if (answer_no) return inject_method.add_exclude;
    } else if (isInArray(excluded_modules, module)) {
        if (answer_yes) return inject_method.add_include;
        if (answer_no) return inject_method.nothing;
    } else {
        if (answer_yes) return inject_method.add_include;
        if (answer_no) return inject_method.add_exclude;
    }
    return inject_method.nothing;
}

pub fn initInjector(
    self: *Injector,
    force_inject: bool,
) !void {
    var lock = try self.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();

    var snippets = try std.ArrayList([]u8).initCapacity(self.allocator, 20);
    defer snippets.deinit(self.allocator);

    for (lock.value.packages) |pkg| {
        try snippets.append(self.allocator, try self.renderInjector(pkg.name));
    }

    try Fs.deleteFileIfExists(Constants.Default.package_files.injector);

    var file = try Fs.openOrCreateFile(Constants.Default.package_files.injector);
    defer file.close();

    const header =
        if (snippets.items.len > 0)
            "const std = @import(\"std\");\npub fn imp(b: *std.Build, exe: *std.Build.Module) void {\n"
        else
            "const std = @import(\"std\");\npub fn imp(_: *std.Build, _: *std.Build.Module) void {\n";

    _ = try file.write(header);
    for (snippets.items) |s| _ = try file.write(s);
    _ = try file.write("}\n");

    try self.injectIntoBuildZig(force_inject);
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
    new_excluded_modules: *std.ArrayList([]const u8),
    new_included_modules: *std.ArrayList([]const u8),
    module_name: []const u8,
    force_inject: bool,
) !inject_method {
    const lock = try self.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();

    const modify_injection = try self.shouldInject(
        module_name,
        lock.value.excluded_modules,
        lock.value.included_modules,
        force_inject,
    );
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
    new_excluded: *std.ArrayList([]const u8),
    new_included: *std.ArrayList([]const u8),
    included_modules: [][]const u8,
    build_param: []const u8,
    module_name: []const u8,
    new_content: *std.ArrayList([]const u8),
    force_inject: bool,
) !void {
    const imported = try self.importModule(
        new_excluded,
        new_included,
        module_name,
        force_inject,
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

pub fn injectIntoBuildZig(
    self: *Injector,
    force_inject: bool,
) !void {
    var lock = try self.manifest.readManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
    );
    defer lock.deinit();
    const included_modules = lock.value.included_modules;
    const excluded_modules = lock.value.excluded_modules;

    if (included_modules.len != 0 or excluded_modules.len != 0) {
        if (!force_inject) return;
    }

    try ZigInit.createZigProject(self.printer, self.allocator, "myproject", null);
    const path = "build.zig";
    var file = try Fs.openFile(path);
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, Constants.Default.mb * 2);
    defer self.allocator.free(content);

    const build_param = try self.findBuildParam(content);

    display_module_blk: {
        self.printer.append("Modules currently imported:\n", .{}, .{ .color = .blue, .weight = .bold });
        if (included_modules.len == 0) {
            self.printer.append(
                " No Modules are importing packages. (not recommended)\n",
                .{},
                .{
                    .color = .red,
                    .weight = .bold,
                },
            );
        }
        for (included_modules) |mod| {
            self.printer.append("  + {s}\n", .{mod}, .{});
        }
        self.printer.append("\n", .{}, .{});

        const answer = try Prompt.input(
            self.allocator,
            self.printer,
            "Keep these imports? (Y/n) ",
            .{},
        );
        const answer_yes = !(answer.len > 0 and (answer[0] == 'n' or answer[0] == 'N'));
        if (answer_yes) {
            self.printer.append("\nOk.\n", .{}, .{});
            return;
        } else {
            self.printer.append("\n", .{}, .{});
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
    const install_prefix = try std.fmt.allocPrint(
        self.allocator,
        install_prefix_fmt,
        .{build_param},
    );
    defer self.allocator.free(install_prefix);

    var split_data = std.mem.splitAny(u8, content, "\n");

    var new_included_modules = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
    defer new_included_modules.deinit(self.allocator);

    var new_excluded_modules = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
    defer new_excluded_modules.deinit(self.allocator);

    while (split_data.next()) |line| {
        if (contains(line, "__zepinj__")) continue;
        if (contains(line, "@import(\".zep/inject\")")) continue;

        try new_content.append(self.allocator, line);
        try new_content.append(self.allocator, "\n");

        // Finish pending multi-line module
        if (current_module) |module| {
            if (!contains(line, ";")) continue;

            try self.maybeInject(
                &new_excluded_modules,
                &new_included_modules,
                included_modules,
                build_param,
                module,
                &new_content,
                force_inject,
            );

            current_module = null;
            continue;
        }

        const module = parseModuleDefinition(
            line,
            install_prefix,
            excluded_modules,
            force_inject,
        ) orelse continue;

        current_module = module;

        if (!contains(line, ";")) continue;

        try self.maybeInject(
            &new_excluded_modules,
            &new_included_modules,
            included_modules,
            build_param,
            module,
            &new_content,
            force_inject,
        );

        current_module = null;
    }

    verify_module_blk: {
        const module_count: u8 = @intCast(new_excluded_modules.items.len + new_included_modules.items.len);
        self.printer.pop(module_count * 2); // pop the prompt, aswell as the answer
        try self.printer.clearLines(module_count);

        self.printer.append("zeP import plan:\n\n", .{}, .{ .color = .blue, .weight = .bold });

        self.printer.append("Will import:\n", .{}, .{});
        var inc_diff = false;
        for (new_included_modules.items) |mod| {
            if (!isInArray(included_modules, mod)) {
                inc_diff = true;
                self.printer.append("  + {s}\n", .{mod}, .{});
            }
        }
        if (!inc_diff) {
            self.printer.append("  # none (new)\n", .{}, .{});
        }

        self.printer.append("\nWill remove:\n", .{}, .{});
        var exc_diff = false;
        for (new_excluded_modules.items) |mod| {
            if (!isInArray(excluded_modules, mod)) {
                exc_diff = true;
                self.printer.append("  - {s}\n", .{mod}, .{});
            }
        }
        if (!exc_diff) {
            self.printer.append("  # none (new)\n", .{}, .{});
        }
        self.printer.append("\n", .{}, .{});

        if (inc_diff or exc_diff) {
            const ans = try Prompt.input(
                self.allocator,
                self.printer,
                "Apply changes? (Y/n) ",
                .{},
            );
            const answer_yes = !(ans.len > 0 and (ans[0] == 'n' or ans[0] == 'N'));
            if (!answer_yes) {
                self.printer.append("Ok.\n", .{}, .{});
                return;
            }
        } else {
            self.printer.append("No changes made.\n", .{}, .{});
            return;
        }

        break :verify_module_blk;
    }

    for (lock.value.included_modules) |i| {
        if (isInArray(new_excluded_modules.items, i)) continue;
        try new_included_modules.append(self.allocator, i);
    }
    for (lock.value.excluded_modules) |i| {
        if (isInArray(new_included_modules.items, i)) continue;
        try new_excluded_modules.append(self.allocator, i);
    }

    lock.value.included_modules = new_included_modules.items;
    lock.value.excluded_modules = new_excluded_modules.items;
    try self.manifest.writeManifest(
        Structs.ZepFiles.Lock,
        Constants.Default.package_files.lock,
        lock.value,
    );

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
}
