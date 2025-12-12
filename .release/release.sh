#!/bin/bash
set -e

VERSION_NAME=$1
if [ $# -eq 0 ]; then
    VERSION_NAME=$(date '+%Y-%m-%d')
fi

RELEASE_DIR="zep.run/releases/$VERSION_NAME"
TEMP_DIR="temp_release"

mkdir -p "$RELEASE_DIR"
mkdir -p "$TEMP_DIR"

# Windows targets
windows_targets=("x86_64-windows" "x86-windows" "aarch64-windows" "x86_64-windows-msvc" "aarch64-windows-msvc")

for target in "${windows_targets[@]}"; do
    zig build -Doptimize=ReleaseFast -freference-trace -Dtarget="$target" -p "$TEMP_DIR/$target"

    zip -j "$RELEASE_DIR/zep_${target}_$VERSION_NAME.zip" "$TEMP_DIR/$target/bin/zep.exe"
done

# Linux targets
linux_targets=("x86_64-linux" "x86-linux" "aarch64-linux" "x86_64-linux-musl" "aarch64-linux-musl")

for target in "${linux_targets[@]}"; do
    zig build -Doptimize=ReleaseFast -freference-trace -Dtarget="$target" -p "$TEMP_DIR/$target"

    tar -C "$TEMP_DIR/$target/bin" -cJf "$RELEASE_DIR/zep_${target}_$VERSION_NAME.tar.xz" zep
done

# macOS targets
macos_targets=("x86_64-macos" "aarch64-macos")

for target in "${macos_targets[@]}"; do
    zig build -Doptimize=ReleaseFast -freference-trace -Dtarget="$target" -p "$TEMP_DIR/$target"

    tar -C "$TEMP_DIR/$target/bin" -cJf "$RELEASE_DIR/zep_${target}_$VERSION_NAME.tar.xz" zep
done

# Clean up temporary build folders
rm -rf "$TEMP_DIR"

echo "Build complete. Releases stored in $RELEASE_DIR"
echo " => Moving now..."
python set_release.py --version $VERSION_NAME
echo "Moving finished, Release completed."
