#!/bin/bash
set -e

usrLocalBin="/usr/local/bin"
lib="/lib"

zepExe="$usrLocalBin/zeP" # zeP executeable (symlink)
zepDir="$lib/zeP"  # main zeP directory
zepZigDir="$zepDir/zig"  # directory for zig version manager
zepVersionDir="$zepDir/v/0.1/"  # directory for current zeP version

tempZepTarDir="/tmp/zeP";  # temporary directory where tar file gets extracted
tempZepTarFile="/tmp/zeP/0.1.tar";  # temporary tar file

###
# Creating required directories
###
defaultSetUp()
{
	mkdir -p "$zepDir"
	mkdir -p "$zepZigDir"
	mkdir -p "$zepVersionDir"

	if [ $EUID != 0 ]; then
			sudo "$0" "$@"
			exit $?
	fi

	mkdir -p "$tempZepTarDir"
}
defaultSetUp


###
# Clear the current data
###
cleanUp()
{
	if [ -e $zepDir ]; then
			rm -rf "$zepDir/*"
	fi

	# remove the current zepExe
	if [ -e $zepExe ]; then
			rm $zepExe
	fi
}


###
# Download the current release
# And extract the tar file
###
downloadAndExtract()
{
	echo "Downloading release..."
	curl -L "https://github.com/XerWoho/zeP/releases/download/0.1/linux_0.1.tar" -o "$tempZepTarFile"


	echo "Extracting..."
	tar -xvf "$tempZepTarFile" -C "$tempZepTarDir"
}

downloadAndExtract



###
# Move smth somewhere 
# and create if it doesnt
# exists
###
safeMoveDir()
{
	FROM=$1
	TO=$2

	if ! [ -e "$FROM/*" ]; then
		mkdir -p "$FROM"
	fi

	# Move folders
	mv "$FROM" "$TO"
}

###
# Set chmod
###
setChmod()
{
	FILE=$1

	chmod ugo-wrx "$FILE"
	chmod +rx "$FILE"
	chmod u+w "$FILE"
}

cleanUp # clean up

safeMoveDir "$tempZepTarDir/packages" "$zepDir/ava"
safeMoveDir "$tempZepTarDir/scripts" "$zepDir/scripts"
mv -f "$tempZepTarDir/zeP" $zepVersionDir
rm -r $tempZepTarDir

setChmod "$zepVersionDir/zeP"
setChmod "$zepDir/scripts/p/path.sh"

echo "Installation complete."
echo "Setting up zeP now."

ln -s "$zepVersionDir/zeP" $zepExe  # create symlink
setChmod $zepExe  # make symlink an exe
$zepExe setup  # run setup script of zeP

echo "Setup complete. On errors, re-run the setup. ($ [sudo] zeP setup)"
