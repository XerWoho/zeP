#!/bin/bash
set -e

usrLocalBin="/usr/local/bin"
lib="/lib"

zepExe="$usrLocalBin/zeP"
zepDir="$lib/zeP"
zepZigDir="$zepDir/zig"

mkdir -p "$zepDir"
mkdir -p "$zepZigDir"

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	exit $?
fi


tempZepTarDir="/tmp/zeP";
mkdir -p "$tempZepTarDir"

tempZepTarVersion="$tempZepTarDir/0.1";
mkdir -p "$tempZepTarVersion"

tempZepTarFile="/tmp/zeP/0.1.tar";


echo "Downloading release..."
curl -L "https://github.com/XerWoho/zeP/releases/download/0.1/linux_0.1.tar" -o "$tempZepTarFile"

echo "Extracting..."
tar -xvf "$tempZepTarFile" -C "$tempZepTarDir"

# clear the current data
if [ -e "$zepDir/*" ]; then
	rm -r "$zepDir/*"
fi

# Move folders
tempZepPackagesFolder="$tempZepTarDir/packages"
destZepPackagesFolder="$zepDir/ava"
mkdir -p "$(dirname "$destZepPackagesFolder")"
mv -f "$tempZepPackagesFolder" "$destZepPackagesFolder"

tempZepScriptsFolder="$tempZepTarDir/scripts"
destZepScriptsFolder="$zepDir/scripts"
mkdir -p "$(dirname "$destZepScriptsFolder")"
mv -f "$tempZepScriptsFolder" "$destZepScriptsFolder"

# remove the current zepExe
if [ -e $zepExe ]; then
	rm $zepExe
fi


tempZepExe="$tempZepTarDir/zeP"
mv -f "$tempZepExe" "$zepExe"
rm -r $tempZepTarDir

chmod ugo-wrx "$zepExe"
chmod +rx "$zepExe"
chmod u+w "$zepExe"

echo "Installation complete."
echo "Setting up zeP now."

/usr/local/bin/zeP setup
echo "Setup complete. On errors, re-run the setup."
