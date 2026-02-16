const std = @import("std");

pub const Controller = struct {
    pub const MissingSubcommand = error{
        Zig,
        Zep,
        Auth,
        PreBuilt,
        Release,
        Package,
        Cmd,
        Cache,
        Custom,
    };

    pub const MissingArguments = error{
        Uninstall,
        Install,
        Custom,
        Info,
        List,
        New,
    };

    pub const Main = error{
        Failed,
    } || MissingSubcommand || MissingArguments;
};

pub const Artifact = error{
    AlreadyInstalled,
    NotInstalled,
    ArtifactNotFound,

    InvalidVersion,
    InvalidUrl,
    InvalidOS,
    InvalidTarball,

    IterFailed,
    FileFailed,
    DirFailed,
    FetchFailed,
    CacheFailed,
    DecompressFailed,
    LockFailed,
    ManifestFailed,
    MetadataFailed,
    SwitchFailed,
    DownloadFailed,
    DeleteFailed,
    LinkingFailed,
    InstallFailed,
    PruneFailed,
} || std.mem.Allocator.Error;

pub const Installable = error{
    AlreadyInstalled,
    NotInstalled,
    PackageNotFound,
    VersionNotFound,

    PackageIsInUse,

    InvalidVersion,
    InvalidPackage,
    InvalidUrl,

    ExtractingFailed,
    ArchivingFailed,
    FetchFailed,
    ResolveFailed,
    CacheFailed,
    HashFailed,
    LockFailed,
    ManifestFailed,
    MetadataFailed,
    ParseFailed,
    DownloadFailed,
    DeleteFailed,
    LinkingFailed,
    InjectFailed,
    InstallFailed,
} || std.mem.Allocator.Error;

pub const Auth = error{
    AlreadyAuthed,
    NotAuthed,

    InvalidPassword,
    PasswordMismatch,
    EmailInUse,
    UsernameInUse,

    FetchFailed,
    ParseFailed,
    ManifestFailed,
} || std.mem.Allocator.Error;

pub const Build = error{
    InvalidVersion,
    InvalidBuild,

    ProcessFailed,
    ZigFailed,
    ManifestFailed,
} || std.mem.Allocator.Error;

pub const Cache = error{
    InvalidFile,
    InvalidDir,

    DirFailed,
    CacheFailed,
} || std.mem.Allocator.Error;

pub const Cmd = error{
    InvalidCmd,

    ProcessFailed,
    ManifestFailed,
} || std.mem.Allocator.Error;

pub const Cloud = error{
    InvalidSelection,
    InvalidUrl,

    NotAuthed,

    FileFailed,
    CompressingFailed,
    FetchFailed,
    ManifestFailed,
} || std.mem.Allocator.Error;

pub const PreBuilt = error{
    InvalidTarget,

    DecompressingFailed,
    CompressingFailed,
    FileFailed,
    DirFailed,
    IterFailed,
} || std.mem.Allocator.Error;
