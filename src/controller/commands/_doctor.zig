const std = @import("std");

const Doctor = @import("../../lib/functions/doctor.zig");

const Context = @import("context");
const Args = @import("args");
const Errors = @import("errors");

fn doctor(ctx: *Context) !void {
    const doctor_args = Args.parseDoctor(ctx.options);
    try Doctor.doctor(ctx, doctor_args.fix);
}

pub fn _doctorController(ctx: *Context) !void {
    doctor(ctx) catch return Errors.Controller.Main.Failed;
}
