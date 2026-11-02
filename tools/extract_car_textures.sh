#!/bin/sh
# Rebuilds the git-ignored textures of the mobile car models on a fresh clone.
#
# Godot extracts each GLB's embedded images to assets/models/cars/mobile/*_Image_*.png
# on import, but skips the extraction when a matching .png.import file already
# exists. Those .import files are committed (they hold the ETC2/ASTC settings)
# while the PNGs are ignored, so a fresh clone never gets the PNGs: the cars then
# ship uncompressed, embedded textures. This script moves the .import files
# aside, forces a reimport of the car GLBs so Godot writes the PNGs, restores the
# committed settings and imports once more.
# Run from the repo root. GODOT defaults to "godot".
# Usage: tools/extract_car_textures.sh   or   GODOT=/path/to/godot tools/extract_car_textures.sh
set -e
G="${GODOT:-godot}"
DIR=assets/models/cars/mobile
BAK="$(mktemp -d)"
trap 'rm -rf "$BAK"' EXIT

for f in "$DIR"/*_Image_*.import; do
  [ -e "$f" ] && mv "$f" "$BAK/"
done
for glb in "$DIR"/*.glb; do
  rm -f .godot/imported/"$(basename "$glb")"-*
done
"$G" --headless --path . --import
mv "$BAK"/*.import "$DIR"/
"$G" --headless --path . --import

n=$(ls "$DIR"/*_Image_*.png 2>/dev/null | wc -l)
echo "Extracted $n car textures in $DIR"
