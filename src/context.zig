const std = @import("std");

const Constants = @import("constants");
const Printer = @import("cli").Printer;
const Manifest = @import("core").Manifest;
const Json = @import("core").Json;
const Fetch = @import("core").Fetch;
const Compressor = @import("core").Compressor;
const Logger = @import("logger");

pub const Context = struct {
    allocator: std.mem.Allocator,
    printer: Printer,
    manifest: Manifest,
    paths: Constants.Paths.Paths,
    fetcher: Fetch,
    json: Json,
    compressor: Compressor,
    logger: *Logger.logly.Logger,
    args: [][:0]u8,

    pub fn deinit(self: *Context) void {
        self.printer.deinit();
        self.paths.deinit();
        self.logger.deinit();
    }
};
