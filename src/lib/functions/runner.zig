const std = @import("std");
const builtin = @import("builtin");

pub const Runner = @This();

const Constants = @import("constants");
const Structs = @import("structs");
const Errors = @import("errors");

const Fs = @import("io").Fs;
const Builder = @import("builder.zig");
const Context = @import("context");

/// Handles running a build
ctx: *Context,

/// Initializes Runner
pub fn init(ctx: *Context) Runner {
    return Runner{
        .ctx = ctx,
    };
}

/// Initializes a Child Processor, and executes specified file
pub fn run(
    self: *Runner,
    target: []const u8,
    args: [][]const u8,
    zig_version: []const u8,
    path: []const u8,
) Errors.Build!void {
    self.ctx.logger.infof("Runner with target={s}, args;", .{target}, @src());
    for (0.., args) |i, arg| {
        self.ctx.logger.infof("({d}) {s}", .{ i, arg }, @src());
    }

    self.ctx.printer.append("Building executeable...\n\n", .{}, .{ .color = .green });
    const target_files = try Builder.build(
        self.ctx,
        path,
        zig_version,
        .{},
    );
    defer self.ctx.allocator.free(target_files);

    var target_file = target_files[0];
    if (target_files.len > 0 and target.len > 0) {
        for (target_files) |tf| {
            if (std.mem.eql(u8, tf, target)) {
                target_file = tf;
                break;
            }
            continue;
        }
    }

    var exec_args = try std.ArrayList([]const u8).initCapacity(self.ctx.allocator, 5);
    for (args) |arg| {
        try exec_args.append(self.ctx.allocator, arg);
    }

    if (builtin.os.tag == .windows) {
        try exec_args.insert(self.ctx.allocator, 0, target_file);
    } else {
        const exec = try std.fmt.allocPrint(
            self.ctx.allocator,
            "./{s}",
            .{target_file},
        );
        defer self.ctx.allocator.free(exec);

        try exec_args.insert(self.ctx.allocator, 0, exec);
    }

    self.ctx.printer.pop(50);

    const cmd = try std.mem.join(self.ctx.allocator, " ", exec_args.items);
    defer self.ctx.allocator.free(cmd);
    self.ctx.logger.info("Running Runner...", @src());
    self.ctx.printer.append("Running...\n $ {s}\n\n ------- \n\n", .{cmd}, .{ .color = .green });

    var process = std.process.Child.init(exec_args.items, self.ctx.allocator);
    const result = process.spawnAndWait() catch return Errors.Build.ProcessFailed;
    if (result.Exited > 0) return Errors.Build.ProcessFailed;

    self.ctx.logger.info("Runner Done.", @src());
}
