const std = @import("std");

const Doctor = @import("../../lib/functions/doctor.zig");
const Context = @import("context").Context;
const Args = @import("args");

fn doctor(
    ctx: *Context,
) !void {
    try ctx.logger.info("running doctor", @src());
    const doctor_args = try Args.parseDoctor();
    try Doctor.doctor(ctx, doctor_args.fix);
    try ctx.logger.info("doctor finished", @src());
    return;
}

pub fn _doctorController(
    ctx: *Context,
) !void {
    try doctor(ctx);
}
