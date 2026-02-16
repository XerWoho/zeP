const std = @import("std");
pub fn imp(b: *std.Build, exe: *std.Build.Module) void {
 // zon.zig MODULE
 const zon_dep = b.dependency("zon", .{});
 exe.addImport("zon", zon_dep.module("zon"));
 // ----------
 // mvzr MODULE
 const mvzr_dep = b.dependency("mvzr", .{});
 exe.addImport("mvzr", mvzr_dep.module("mvzr"));
 // ----------
 // logly.zig MODULE
 const logly_dep = b.dependency("logly", .{});
 exe.addImport("logly", logly_dep.module("logly"));
 // ----------
}
