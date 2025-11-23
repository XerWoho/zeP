#!/bin/bash
zig build -Doptimize=ReleaseFast -freference-trace -Dtarget=x86_64-windows-msvc -p tempR/w
zig build -Doptimize=ReleaseFast -freference-trace -Dtarget=x86_64-linux-gnu -p tempR/l
mkdir -p release
mkdir -p release/w
mkdir -p release/l

# 536b43b67b18ce160a8043065523c8d5a198745da9d4fd86abd2bbe50499fea4

versionName=$1
if [ $# -eq 0 ]
  then
	date=$(date '+%Y-%m-%d')
	versionName="$date"
fi


zip -j release/w/windows_$versionName.zip tempR/w/bin/zeP.exe
zip -r release/w/windows_$versionName.zip packages/

tar -C tempR/l/bin -cvf release/l/linux_$versionName.tar zeP
tar -rf release/l/linux_$versionName.tar packages/

rm -r tempR/