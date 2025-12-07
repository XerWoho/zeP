#!/bin/bash
versionName=$1

if [ $# -eq 0 ]; then
    versionName=$(date '+%Y-%m-%d')
fi

mkdir -p release
mkdir -p tempR

# Windows targets
windows_targets=("x86_64-windows" "x86-windows" "aarch64-windows")

for element in "${windows_targets[@]}"; do
    mkdir -p release/$element

    zig build -Doptimize=ReleaseFast -freference-trace -Dtarget=$element -p tempR/$element

    zip -j release/$element/zep_${element}_$versionName.zip tempR/$element/bin/zeP.exe
    zip -r release/$element/zep_${element}_$versionName.zip packages/
done

# Linux targets
linux_targets=("x86_64-linux" "x86-linux" "aarch64-linux" "x86_64-linux-musl" "aarch64-linux-musl")

for element in "${linux_targets[@]}"; do
    mkdir -p release/$element

    zig build -Doptimize=ReleaseFast -freference-trace -Dtarget=$element -p tempR/$element

	tar -C tempR/$element/bin -cJf release/$element/zep_${element}_$versionName.tar.xz zeP ../../../packages/
done

rm -r tempR/