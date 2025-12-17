const std = @import("std");
pub fn imp(b: *std.Build, exe: *std.Build.Module) void {
 // clap MODULE
 const clapMod = b.createModule(.{
     .root_source_file = b.path(".zep/clap/clap.zig"),
 });
 exe.addImport("clap", clapMod);
 // ----------
 // logly MODULE
 const loglyMod = b.createModule(.{
     .root_source_file = b.path(".zep/logly/src/logly.zig"),
 });
 exe.addImport("logly", loglyMod);
 // ----------
}
