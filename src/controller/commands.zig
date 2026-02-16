const std = @import("std");
pub const Commands = enum {
    self,
    zep,
    zig,

    auth,
    cache,
    cmd,
    doctor,
    inject,

    upgrade,
    install,
    add,
    uninstall,
    remove,

    custom,
    info,
    list,

    package,
    release,

    paths,
    prebuilt,
    prebuild,
    purge,
    version,
    runner,
    run, // (hidden) alternative

    builder,
    build, // (hidden) alternative
    bootstrap,
    init,
    config,
};
