const std = @import("std");

const Constants = @import("constants");
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json;
const Fetch = @import("core").Fetch;
const Compressor = @import("core").Compressor;
const Logger = @import("logger");

pub const Context = @This();

allocator: std.mem.Allocator,
printer: Printer,
manifest: Manifest,
paths: Constants.Paths.Paths,
fetcher: Fetch,
compressor: Compressor,
logger: Logger.Wrapper,
args: [][:0]u8,
options: [][]const u8,
cmds: [][]const u8,

pub fn deinit(self: *Context) void {
    self.printer.deinit();
    self.paths.deinit();
    self.logger.deinit();

    self.allocator.free(self.cmds);
    self.allocator.free(self.options);
}
