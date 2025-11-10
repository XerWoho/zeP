const std = @import("std");

const Constants = @import("constants");
const UtilsPackage =
    @import("package.zig");
const UtilsJson =
    @import("json.zig");
const UtilsFs =
    @import("fs.zig");
const UtilsPrinter =
    @import("printer.zig");

pub const Injector = struct {
    allocator: std.mem.Allocator,
    packageName: []const u8,
    printer: *UtilsPrinter.Printer,

    pub fn init(allocator: std.mem.Allocator, packageName: []const u8, printer: *UtilsPrinter.Printer) Injector {
        return Injector{ .allocator = allocator, .packageName = packageName, .printer = printer };
    }

    fn injector(self: *Injector, packageName: []const u8, pathName: []const u8) ![]u8 {
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

        const replacedPath = try std.mem.replaceOwned(u8, self.allocator, template, "{path}", pathName);
        defer self.allocator.free(replacedPath);

        const replacedName = try std.mem.replaceOwned(u8, self.allocator, replacedPath, "{name}", packageName);
        return replacedName;
    }

    pub fn initInjector(self: *Injector) !void {
        var json = try UtilsJson.Json.init(self.allocator);
        const pkgJsonOpt = try json.parsePkgJson();
        if (pkgJsonOpt == null) {
            try self.printer.append("NO PACKAGE JSON! INIT PLEASE!\n\n");
            return;
        }

        const pkgJson = pkgJsonOpt.?;
        defer pkgJson.deinit();

        var injectedPkgs = std.ArrayList([]u8).init(self.allocator);
        defer injectedPkgs.deinit();

        for (pkgJson.value.packages) |p| {
            const parsedPkg = try json.parsePackage(p);
            if (parsedPkg == null) continue;
            const parsed = parsedPkg.?;
            defer parsed.deinit();

            const inj = try self.injector(p, parsed.value.root_file);
            try injectedPkgs.append(inj);
        }

        const totalPkgs = try injectedPkgs.toOwnedSlice();
        const injectorEnd = "}";

        if (try UtilsFs.checkFileExists(Constants.ZEP_INJECTOR))
            try UtilsFs.delFile(Constants.ZEP_INJECTOR);

        const injectorFile = try UtilsFs.openCFile(Constants.ZEP_INJECTOR);
        defer injectorFile.close();

        const injectorStart = if (totalPkgs.len >= 1)
            "const std = @import(\"std\");\npub fn injectExtraImports(b: *std.Build, exe: *std.Build.Step.Compile) void {"
        else
            "const std = @import(\"std\");\npub fn injectExtraImports(_: *std.Build, _: *std.Build.Step.Compile) void {";

        _ = try injectorFile.write(injectorStart);
        for (totalPkgs) |p| {
            _ = try injectorFile.write(p);
        }
        _ = try injectorFile.write(injectorEnd);

        try self.injectIntoBuildZig();
    }

    pub fn injectIntoBuildZig(self: *Injector) !void {
        const path = "build.zig";
        if (!try UtilsFs.checkFileExists(path)) {
            // init zig
            const argv = &[2][]const u8{ "zig", "init" };
            var process = std.process.Child.init(argv, self.allocator);
            try process.spawn();
            _ = try process.wait();
            _ = try process.kill();
            try self.printer.append("\nInitted zig project...\n");
        }

        var file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const injectLine = "    @import(\".zep/inject.zig\").injectExtraImports(b, exe);\n";
        if (std.mem.containsAtLeast(u8, content, 1, injectLine))
            return;

        const insertBefore = "    b.installArtifact(exe);";
        const idx = std.mem.indexOf(u8, content, insertBefore) orelse return error.MissingInstallCall;

        try file.seekTo(0);
        try file.setEndPos(0);
        _ = try file.writeAll(content[0..idx]);
        _ = try file.writeAll(injectLine);
        _ = try file.writeAll(content[idx..]);
    }
};
