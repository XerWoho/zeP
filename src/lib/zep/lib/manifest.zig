const std = @import("std");

const Utils = @import("utils");
const UtilsFs = Utils.UtilsFs;

const Constants = @import("constants");
const Structs = @import("structs");

const MAX_SIZE = 1028 * 1028 * 10;

/// Overwrites the Zep manifest with the provided version information
pub fn modifyManifest(version: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // Remove old manifest if it exists
    try UtilsFs.delFile(Constants.ROOT_ZEP_ZIG_MANIFEST);

    // Build the path for the installed Zep version
    const path = try std.fmt.allocPrint(allocator, "{s}/v/{s}/", .{ Constants.ROOT_ZEP_ZEP_FOLDER, version });

    // Create new manifest struct
    const newManifest = Structs.ZepManifest{
        .version = version,
        .path = path,
    };

    // Serialize to JSON
    const jsonStr = try std.json.stringifyAlloc(allocator, newManifest, .{ .whitespace = .indent_tab });

    // Write to manifest file
    const f = try UtilsFs.openCFile(Constants.ROOT_ZEP_ZEP_MANIFEST);
    defer f.close();

    _ = try f.write(jsonStr);
}

/// Reads and parses the Zep manifest
pub fn getManifest() !std.json.Parsed(Structs.ZepManifest) {
    const allocator = std.heap.page_allocator;

    if (!try UtilsFs.checkFileExists(Constants.ROOT_ZEP_ZEP_MANIFEST)) {
        return error.NoManifestFile;
    }

    const f = try UtilsFs.openFile(Constants.ROOT_ZEP_ZEP_MANIFEST);
    defer f.close();

    const data = try f.readToEndAlloc(allocator, MAX_SIZE);

    const parsed = try std.json.parseFromSlice(Structs.ZepManifest, allocator, data, .{});
    return parsed;
}
