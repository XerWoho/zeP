#!/bin/bash

lib="/lib"
usrLocalBin="/usr/local/bin"
zepDir="$lib/zeP"
zepZigDir="$zepDir/zig"
zepZigExe="$zepZigDir/zig.exe"

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	currentPath=$PATH
	if ! [[ $currentPath == *"$zepZigDir"* ]]; then 
			echo "Setting PATH" 
			export PATH="$zepZigDir:$PATH"
			echo $PATH
	fi
	exit $?
fi

if ! [ -e $zepDir ]; then
	mkdir $zepDir
			exit
fi

if ! [ -e $zepZigDir ]; then
	mkdir $zepZigDir
			exit
fi

if [ $# -eq 0 ]; then
	echo "No arguments supplied"
			exit
fi
target=$1

if ! [ -e $target ]; then
	echo "Target does not exist!"
			exit       
fi

if [ -e $zepZigExe ]; then
	rm $zepZigExe
fi

ln -s $target $zepZigExe
