#!/bin/sh
# Builds assets/animations/mixamo_library.res from the Mixamo clips in
# assets/animations/mixamo/ (both git-ignored: Mixamo's terms forbid sharing
# them). Run from the repo root. GODOT defaults to "godot".
# Usage: tools/build_mixamo_library.sh   or   GODOT=/c/Godot/godot.exe tools/build_mixamo_library.sh
set -e
G="${GODOT:-godot}"
L="$(dirname "$0")/locked.sh"
sh "$L" "$G" --headless --path . --import
sh "$L" "$G" --headless --path . --script scripts/mixamo_library_build.gd -- --write-imports
sh "$L" "$G" --headless --path . --import
sh "$L" "$G" --headless --path . --script scripts/mixamo_library_build.gd
