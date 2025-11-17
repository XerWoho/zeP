#!/bin/bash
set -e

USR_LOCAL_BIN="/usr/local/bin"
LIB="/lib"


TARGET="0.2" # latest version
if [ $# -eq 0 ]; then
	TARGET="$1"
fi

ZEP_EXE="$USR_LOCAL_BIN/zeP" # zeP executeable (symlink)
ZEP_DIR="$LIB/zeP"  # main zeP directory
ZEP_ZIG_DIR="$ZEP_DIR/zig"  # directory for zig version manager
ZEP_VERSION_DIR="$ZEP_DIR/zep/v/$TARGET/"  # directory for current zeP version
MANIFEST_ZEP="$ZEP_DIR/zep/manifest.json"

TEMP_ZEP_TAR_DIR="/tmp/zeP";  # temporary directory where tar file gets extracted
TEMP_ZEP_TAR_FILE="/tmp/zeP/$TARGET.tar";  # temporary tar file

###
# Creating required directories
###
default_setup()
{
	mkdir -p "$ZEP_DIR"
	mkdir -p "$ZEP_ZIG_DIR"
	mkdir -p "$ZEP_VERSION_DIR"

	if [ $EUID != 0 ]; then
			sudo "$0" "$@"
			exit $?
	fi

	mkdir -p "$TEMP_ZEP_TAR_DIR"

	JSON_STRING="{
	\"version\":\"${TARGET}\",
	\"path\":\"${ZEP_VERSION_DIR}\",
	}"

	echo "$JSON_STRING" > $MANIFEST_ZEP
}
default_setup


###
# Clear the current data
###
clean_up()
{
	if [ -e $ZEP_DIR ]; then
			rm -rf "${ZEP_DIR:?}/*"
	fi

	# remove the current ZEP_EXE
	if [ -e $ZEP_EXE ]; then
			rm $ZEP_EXE
	fi
}


###
# Download the current release
# And extract the tar file
###
download_and_extract()
{
	echo "Downloading release..."
	curl -L "https://github.com/XerWoho/zeP/releases/download/$TARGET/linux_$TARGET.tar" -o "$TEMP_ZEP_TAR_FILE"


	echo "Extracting..."
	tar -xvf "$TEMP_ZEP_TAR_FILE" -C "$TEMP_ZEP_TAR_DIR"
}

download_and_extract



###
# Move smth somewhere 
# and create if it doesnt
# exists
###
safe_move_dir()
{
	local src=$1
	local dest=$2

	if [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
		mkdir -p "$src"
	fi

	# Move folders
	mv "$src" "$dest"
}

clean_up # clean up

chmod 755 "$ZEP_VERSION_DIR/zeP"
chmod 755 "$ZEP_VERSION_DIR/scripts/p/path.sh"

echo "Installation complete."
echo "Setting up zeP now."

ln -s "$ZEP_VERSION_DIR/zeP" $ZEP_EXE  # create symlink
chmod 755 $ZEP_EXE  # make symlink an exe
$ZEP_EXE setup  # run setup script of zeP

echo "Setup complete. On errors, re-run the setup. ($ [sudo] zeP setup)"
