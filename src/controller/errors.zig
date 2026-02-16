const Errors = @import("errors");
const Context = @import("context");
const Structs = @import("structs");

pub fn handleArtifactError(
    ctx: *Context,
    err: Errors.Artifact,
    action: []const u8,
    version: ?[]const u8,
) void {
    switch (err) {
        error.ArtifactNotFound => {
            ctx.logger.err("Url not found...", @src());
            ctx.printer.append("Url was not found.\n\n", .{}, .{});
        },
        error.InvalidVersion => {
            ctx.printer.append(
                "Version {s} was not found.\n\n",
                .{version orelse "unknown"},
                .{},
            );
        },
        error.NotInstalled => {
            ctx.printer.append(
                "Version {s} is not installed.\n\n",
                .{version orelse "unknown"},
                .{},
            );
        },
        error.InvalidOS => {
            ctx.printer.append(
                "Invalid Operating System.\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} failed...", .{action}, @src());
            ctx.printer.append(
                "{s} failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handleAuthError(
    ctx: *Context,
    err: Errors.Auth,
    action: []const u8,
) void {
    switch (err) {
        error.AlreadyAuthed => {
            ctx.logger.err("Already authenticated...", @src());
            ctx.printer.append("Already Authed.\n\n", .{}, .{});
        },
        error.NotAuthed => {
            ctx.printer.append(
                "Not authenticated...\n\n",
                .{},
                .{},
            );
        },
        error.EmailInUse => {
            ctx.printer.append(
                "Email already in use.\n\n",
                .{},
                .{},
            );
        },
        error.UsernameInUse => {
            ctx.printer.append(
                "Username already in use.\n",
                .{},
                .{},
            );
        },
        error.InvalidPassword => {
            ctx.printer.append(
                "Invalid Password.\n",
                .{},
                .{},
            );
        },
        error.PasswordMismatch => {
            ctx.printer.append(
                "Passwords do NOT match.\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} failed...", .{action}, @src());
            ctx.printer.append(
                "{s} failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handleBuildError(
    ctx: *Context,
    err: Errors.Build,
) void {
    switch (err) {
        error.InvalidVersion => {
            ctx.logger.err("Invalid Zig Version...", @src());
            ctx.printer.append("Invalid Zig Version.\n\n", .{}, .{});
        },
        error.InvalidBuild => {
            ctx.printer.append(
                "Invalid Build.\n\n",
                .{},
                .{},
            );
        },
        error.ProcessFailed => {
            ctx.printer.append(
                "Process Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ZigFailed => {
            ctx.printer.append(
                "Zig Failed.\n",
                .{},
                .{},
            );
        },
        error.ManifestFailed => {
            ctx.printer.append(
                "Manifest Failed.\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("Building failed...", .{}, @src());
            ctx.printer.append(
                "Building failed.\n\n",
                .{},
                .{},
            );
        },
    }
}

pub fn handleCacheError(
    ctx: *Context,
    err: Errors.Cache,
    action: []const u8,
) void {
    switch (err) {
        error.InvalidFile => {
            ctx.logger.err("Invalid File...", @src());
            ctx.printer.append("Invalid File.\n\n", .{}, .{});
        },
        error.InvalidDir => {
            ctx.printer.append(
                "Invalid Directory.\n\n",
                .{},
                .{},
            );
        },
        error.DirFailed => {
            ctx.printer.append(
                "Directory Iteration Failed.\n",
                .{},
                .{},
            );
        },
        error.CacheFailed => {
            ctx.printer.append(
                "Caching Failed.\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} failed...", .{action}, @src());
            ctx.printer.append(
                "{s} failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handleCmdError(
    ctx: *Context,
    err: Errors.Cmd,
    action: []const u8,
) void {
    switch (err) {
        error.InvalidCmd => {
            ctx.logger.err("Invalid Command...", @src());
            ctx.printer.append("Invalid Command.\n\n", .{}, .{});
        },
        error.ProcessFailed => {
            ctx.printer.append(
                "Process Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ManifestFailed => {
            ctx.printer.append(
                "Manifest Failed.\n\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} failed...", .{action}, @src());
            ctx.printer.append(
                "{s} failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handleInstallableError(
    ctx: *Context,
    err: Errors.Installable,
    action: []const u8,
) void {
    switch (err) {
        error.AlreadyInstalled => {
            ctx.logger.err("Already installed...", @src());
            ctx.printer.append("Already installed.\n\n", .{}, .{});
        },
        error.NotInstalled => {
            ctx.printer.append(
                "Not Installed.\n\n",
                .{},
                .{},
            );
        },
        error.PackageNotFound => {
            ctx.printer.append(
                "Package not found.\n\n",
                .{},
                .{},
            );
        },
        error.VersionNotFound => {
            ctx.printer.append(
                "Version not found.\n\n",
                .{},
                .{},
            );
        },
        error.PackageIsInUse => {
            ctx.printer.append(
                "Package is in use.\n\n",
                .{},
                .{},
            );
        },
        error.InvalidVersion => {
            ctx.printer.append(
                "Invalid version.\n\n",
                .{},
                .{},
            );
        },
        error.InvalidPackage => {
            ctx.printer.append(
                "Invalid package.\n\n",
                .{},
                .{},
            );
        },
        error.InvalidUrl => {
            ctx.printer.append(
                "Invalid Url.\n\n",
                .{},
                .{},
            );
        },
        error.FetchFailed => {
            ctx.printer.append(
                "Fetching Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ResolveFailed => {
            ctx.printer.append(
                "Resolving Failed.\n\n",
                .{},
                .{},
            );
        },
        error.CacheFailed => {
            ctx.printer.append(
                "Cache Failed.\n\n",
                .{},
                .{},
            );
        },
        error.HashFailed => {
            ctx.printer.append(
                "Hash Failed.\n\n",
                .{},
                .{},
            );
        },
        error.LockFailed => {
            ctx.printer.append(
                "Lock Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ManifestFailed => {
            ctx.printer.append(
                "Manifest Failed.\n\n",
                .{},
                .{},
            );
        },
        error.MetadataFailed => {
            ctx.printer.append(
                "Metadata Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ParseFailed => {
            ctx.printer.append(
                "Parsing Failed.\n\n",
                .{},
                .{},
            );
        },
        error.DownloadFailed => {
            ctx.printer.append(
                "Downloading Failed.\n\n",
                .{},
                .{},
            );
        },
        error.DeleteFailed => {
            ctx.printer.append(
                "Deleting Failed.\n\n",
                .{},
                .{},
            );
        },
        error.LinkingFailed => {
            ctx.printer.append(
                "Linking Failed.\n\n",
                .{},
                .{},
            );
        },
        error.InjectFailed => {
            ctx.printer.append(
                "Injecting Failed.\n\n",
                .{},
                .{},
            );
        },
        error.InstallFailed => {
            ctx.printer.append(
                "Installing Failed.\n\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} Failed...", .{action}, @src());
            ctx.printer.append(
                "{s} Failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handleCloudError(
    ctx: *Context,
    err: Errors.Cloud,
    action: []const u8,
) void {
    switch (err) {
        error.InvalidSelection => {
            ctx.logger.err("Invalid selection...", @src());
            ctx.printer.append("Invalid selection.\n\n", .{}, .{});
        },
        error.InvalidUrl => {
            ctx.printer.append(
                "Invalid Url.\n\n",
                .{},
                .{},
            );
        },
        error.NotAuthed => {
            ctx.printer.append(
                "Not authenticated.\n\n",
                .{},
                .{},
            );
        },
        error.FileFailed => {
            ctx.printer.append(
                "File Failed.\n\n",
                .{},
                .{},
            );
        },
        error.CompressingFailed => {
            ctx.printer.append(
                "Compressing Failed.\n\n",
                .{},
                .{},
            );
        },
        error.FetchFailed => {
            ctx.printer.append(
                "Fetching Failed.\n\n",
                .{},
                .{},
            );
        },
        error.ManifestFailed => {
            ctx.printer.append(
                "Manifest Failed.\n\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} Failed...", .{action}, @src());
            ctx.printer.append(
                "{s} Failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}

pub fn handlePreBuiltError(
    ctx: *Context,
    err: Errors.PreBuilt,
    action: []const u8,
) void {
    switch (err) {
        error.InvalidTarget => {
            ctx.logger.err("Invalid target...", @src());
            ctx.printer.append("Invalid target.\n\n", .{}, .{});
        },
        error.DecompressingFailed => {
            ctx.printer.append(
                "Decompressing Failed.\n\n",
                .{},
                .{},
            );
        },
        error.CompressingFailed => {
            ctx.printer.append(
                "Compressing Failed.\n\n",
                .{},
                .{},
            );
        },
        error.FileFailed => {
            ctx.printer.append(
                "File Failed.\n\n",
                .{},
                .{},
            );
        },
        error.DirFailed => {
            ctx.printer.append(
                "Dir Failed.\n\n",
                .{},
                .{},
            );
        },
        error.IterFailed => {
            ctx.printer.append(
                "Iter Failed.\n\n",
                .{},
                .{},
            );
        },
        else => {
            ctx.logger.errorf("{s} Failed...", .{action}, @src());
            ctx.printer.append(
                "{s} Failed.\n\n",
                .{action},
                .{},
            );
        },
    }
}
