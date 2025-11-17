#!/bin/bash

USR_LOCAL_BIN="/usr/local/bin"
LIB="/lib"
ZEP_DIR="$LIB/zeP"
ZEP_ZIG_DIR="$ZEP_DIR/zig"
ZEP_ZIG_EXE="$USR_LOCAL_BIN/zig"

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	local currentPath="$PATH"
	if ! [[ $currentPath == *"$ZEP_ZIG_DIR"* ]]; then 
			echo "Setting PATH" 
			export PATH="$ZEP_ZIG_DIR:$PATH"
			echo $PATH
	fi
	exit $?
fi

if ! [ -d "$ZEP_DIR" ]; then
	mkdir "$ZEP_DIR"
			exit
fi

if ! [ -d "$ZEP_ZIG_DIR" ]; then
	mkdir "$ZEP_ZIG_DIR"
			exit
fi

if [ $# -eq 0 ]; then
	echo "No arguments supplied"
			exit
fi
TARGET="$1"

if ! [ -e "$TARGET" ]; then
	echo "Target does not exist!"
			exit       
fi

if [ -e "$ZEP_ZIG_EXE" ]; then
	rm "$ZEP_ZIG_EXE"
fi

ln -s "$TARGET" "$ZEP_ZIG_EXE"
chmod +x "$ZEP_ZIG_EXE"