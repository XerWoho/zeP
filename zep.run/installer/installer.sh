#!/bin/bash

USR_LOCAL_BIN="$HOME/.local/bin"
export PATH="$USR_LOCAL_BIN:$PATH"
grep -qxF "export PATH=\"$USR_LOCAL_BIN:\$PATH\"" "$HOME/.bashrc" || echo "export PATH=\"$USR_LOCAL_BIN:\$PATH\"" >> "$HOME/.bashrc"


LOCAL_ZEP="$HOME/.local"
if ! [ -e "$LOCAL_ZEP" ]; then
    mkdir -p "${LOCAL_ZEP}"
fi

if ! [ -e "$USR_LOCAL_BIN" ]; then
    mkdir -p "${USR_LOCAL_BIN}"
fi

OLD_LOCAL_ZEP="/lib/zeP"
if [ -e "$OLD_LOCAL_ZEP" ]; then
    sudo mv "${OLD_LOCAL_ZEP}" "${LOCAL_ZEP}"
fi



TARGET="0.7"
if [ $# -gt 0 ]; then
    TARGET="$1"
fi

ZEP_EXE="$USR_LOCAL_BIN/zep"
ZIG_EXE="$USR_LOCAL_BIN/zig"
ZEP_DIR="$LOCAL_ZEP/zep"
ZEP_ZIG_DIR="$ZEP_DIR/zig"
ZEP_VERSION_DIR="$ZEP_DIR/zep/d/$TARGET/x86_64-linux"
MANIFEST_ZEP="$ZEP_DIR/zep/manifest.json"

TEMP_DIR="/tmp/zeP"
TEMP_ZEP_TAR_FILE="$TEMP_DIR/$TARGET.tar.xz"

sudo rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

###
# Clear everything FIRST
###
clean_up() {
    sudo rm -rf "$ZEP_VERSION_DIR"
}
clean_up

###
# Create directories
###
mkdir -p "$ZEP_VERSION_DIR"
mkdir -p "$ZEP_ZIG_DIR"

JSON_STRING="{
    \"name\":\"zep_x86_64-linux_${TARGET}\",
    \"path\":\"${ZEP_VERSION_DIR}\"
}"

mkdir -p "$(dirname "$MANIFEST_ZEP")"
echo "$JSON_STRING" > "$MANIFEST_ZEP"

###
# Download and extract
###
echo "Downloading release..."

curl -L "https://zep.run/releases/$TARGET/zep_x86_64-linux_$TARGET.tar.xz" \
    -o "$TEMP_ZEP_TAR_FILE"

echo "Extracting..."
tar -xvf "$TEMP_ZEP_TAR_FILE" -C "$ZEP_VERSION_DIR"
ZEP_VERSION_EXE=$ZEP_VERSION_DIR/zeP
if [ -e "$ZEP_VERSION_DIR/zep" ]; then
    ZEP_VERSION_EXE=$ZEP_VERSION_DIR/zeP
fi

chmod 755 "$ZEP_VERSION_EXE"
echo "Installation complete."
echo "Setting up zeP now."

sudo rm -rf "$ZEP_EXE"

sudo ln -s "$ZEP_VERSION_EXE" "$ZEP_EXE"
sudo chmod 755 "$ZEP_VERSION_EXE"
"$ZEP_EXE" setup

echo "Setup complete."
