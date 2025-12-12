const std = @import("std");
pub fn injectExtraImports(b: *std.Build, exe: *std.Build.Step.Compile) void { 
 // clap MODULE 
 const clapMod = b.createModule(.{ 
 .root_source_file = b.path(".zep/clap/clap.zig"), 
 }); 
 exe.root_module.addImport("clap", clapMod); 
 // ---------- 
}