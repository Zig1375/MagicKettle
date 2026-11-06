#!/bin/sh
# Builds tools/powershell/powershell.c into the MagicKettleKit resources that `PowerShell` installs: a 64-bit one
# for system32 and a 32-bit one for syswow64. Needs `brew install mingw-w64`. The results are committed, so
# building Magic Kettle doesn't need MinGW.
set -eu
cd "$(dirname "$0")/.."
x86_64-w64-mingw32-gcc -O2 -municode -static -s \
    -o Sources/MagicKettleKit/Resources/powershell-x64.exe tools/powershell/powershell.c -ladvapi32
i686-w64-mingw32-gcc -O2 -municode -static -s \
    -o Sources/MagicKettleKit/Resources/powershell-x86.exe tools/powershell/powershell.c -ladvapi32
shasum -a 256 Sources/MagicKettleKit/Resources/powershell-x64.exe Sources/MagicKettleKit/Resources/powershell-x86.exe
