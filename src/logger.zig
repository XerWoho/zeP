const std = @import("std");
const Constants = @import("constants");

pub const logly = @import("logly");

pub var logger_instance: ?*logly.Logger = null;

pub fn init(
    alloc: std.mem.Allocator,
    log_location: []u8,
) !void {
    if (logger_instance != null) return;

    var config = logly.Config.default();
    config.auto_sink = false;
    config.check_for_updates = false;
    config.console = false;
    config.debug_mode = false;
    config.global_console_display = false;

    const logger = try logly.Logger.initWithConfig(alloc, config);
    logger.configure(config);

    _ = try logger.add(.{
        .path = log_location,
        .size_limit = 10 * Constants.Default.mb,
        .retention = 5,
    });

    try logger.bind("app", .{ .string = "zep" });
    try logger.bind("version", .{ .string = Constants.Default.version });

    logger_instance = logger;
}

pub fn deinit() void {
    if (logger_instance) |*l| {
        l.deinit();
        logger_instance = null;
    }
}

pub fn get() *logly.Logger {
    return logger_instance orelse
        @panic("Logger used before init");
}

pub const Wrapper = struct {
    logger: *logly.Logger,

    pub fn init(logger: *logly.Logger) Wrapper {
        return .{
            .logger = logger,
        };
    }

    pub fn deinit(self: *Wrapper) void {
        self.logger.deinit();
    }

    pub fn info(self: *Wrapper, message: []const u8, src: ?std.builtin.SourceLocation) void {
        self.logger.info(message, src) catch {};
    }

    pub fn err(self: *Wrapper, message: []const u8, src: ?std.builtin.SourceLocation) void {
        self.logger.err(message, src) catch {};
    }

    pub fn debug(self: *Wrapper, message: []const u8, src: ?std.builtin.SourceLocation) void {
        self.logger.debug(message, src) catch {};
    }

    pub fn warn(self: *Wrapper, message: []const u8, src: ?std.builtin.SourceLocation) void {
        self.logger.warn(message, src) catch {};
    }

    pub fn infof(self: *Wrapper, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) void {
        self.logger.infof(fmt, args, src) catch {};
    }

    pub fn errorf(self: *Wrapper, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) void {
        self.logger.errorf(fmt, args, src) catch {};
    }

    pub fn debugf(self: *Wrapper, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) void {
        self.logger.debugf(fmt, args, src) catch {};
    }

    pub fn warnf(self: *Wrapper, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) void {
        self.logger.warnf(fmt, args, src) catch {};
    }
};
