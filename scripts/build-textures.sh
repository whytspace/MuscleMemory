#!/usr/bin/env bash
#
# Convert every PNG in Assets/ to an uncompressed 32-bit TGA the WoW client can
# load. Safe to run repeatedly — it overwrites the matching .tga each time.
#
# Each image is fit into a power-of-two square (default 256) with transparent
# padding, preserving aspect, 8-bit RGBA. Pass a size to override:
#
#   scripts/build-textures.sh        # 256x256
#   scripts/build-textures.sh 512    # 512x512
#
# Requires ImageMagick (`brew install imagemagick`).

set -euo pipefail

SIZE="${1:-256}"
ASSETS_DIR="$(cd "$(dirname "$0")/../Assets" && pwd)"

if command -v magick >/dev/null 2>&1; then
  MAGICK=(magick)
elif command -v convert >/dev/null 2>&1; then
  MAGICK=(convert)
else
  echo "ImageMagick not found. Install it with: brew install imagemagick" >&2
  exit 1
fi

shopt -s nullglob
pngs=("$ASSETS_DIR"/*.png)
if [ ${#pngs[@]} -eq 0 ]; then
  echo "No PNGs found in $ASSETS_DIR"
  exit 0
fi

for png in "${pngs[@]}"; do
  tga="${png%.png}.tga"
  "${MAGICK[@]}" "$png" \
    -alpha on \
    -resize "${SIZE}x${SIZE}" \
    -background none -gravity center -extent "${SIZE}x${SIZE}" \
    -depth 8 -type TrueColorAlpha -compress none \
    "TGA:$tga"
  echo "  $(basename "$png") -> $(basename "$tga")  (${SIZE}x${SIZE})"
done

echo "Done. Converted ${#pngs[@]} file(s) at ${SIZE}x${SIZE}."
