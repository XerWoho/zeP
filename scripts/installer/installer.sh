#!/bin/bash
set -e

USR_LOCAL_BIN="/usr/local/bin"
LIB="/lib"

TARGET="0.3"
if [ $# -gt 0 ]; then
    TARGET="$1"
fi

ZEP_EXE="$USR_LOCAL_BIN/zeP"
ZIG_EXE="$USR_LOCAL_BIN/zig"
ZEP_DIR="$LIB/zeP"
ZEP_ZIG_DIR="$ZEP_DIR/zig"
ZEP_VERSION_DIR="$ZEP_DIR/zep/v/$TARGET"
MANIFEST_ZEP="$ZEP_DIR/zep/manifest.json"

TEMP_DIR="/tmp/zeP"
TEMP_ZEP_TAR_FILE="$TEMP_DIR/$TARGET.tar"

mkdir -p "$TEMP_DIR"

###
# Clear everything FIRST
###
clean_up() {
    rm -rf "$ZEP_DIR"
    rm -f "$ZEP_EXE"
    rm -f "$ZIG_EXE"
}
clean_up

###
# Create directories
###
mkdir -p "$ZEP_VERSION_DIR"
mkdir -p "$ZEP_ZIG_DIR"

JSON_STRING="{
    \"version\":\"${TARGET}\",
    \"path\":\"${ZEP_VERSION_DIR}\"
}"

mkdir -p "$(dirname "$MANIFEST_ZEP")"
echo "$JSON_STRING" > "$MANIFEST_ZEP"

###
# Download and extract
###
echo "Downloading release..."
curl -L "https://github.com/XerWoho/zeP/releases/download/$TARGET/linux_$TARGET.tar" \
    -o "$TEMP_ZEP_TAR_FILE"

echo "Extracting..."
tar -xvf "$TEMP_ZEP_TAR_FILE" -C "$ZEP_VERSION_DIR"

chmod 755 "$ZEP_VERSION_DIR/zeP"

echo "Installation complete."
echo "Setting up zeP now."

ln -s "$ZEP_VERSION_DIR/zeP" "$ZEP_EXE"
chmod 755 "$ZEP_EXE"
"$ZEP_EXE" setup

echo "Setup complete."
