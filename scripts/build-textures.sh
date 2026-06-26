#!/usr/bin/env bash
#
# Build the WoW-loadable textures in Assets/. Any SVG source is first rasterized
# to a PNG (the vector origin for our icons); then every PNG is converted to an
# uncompressed 32-bit TGA the client can load. Safe to run repeatedly — it
# overwrites the matching .png/.tga each time.
#
# Each image is fit into a power-of-two square (default 256) with transparent
# padding, preserving aspect, 8-bit RGBA. Pass a size to override:
#
#   scripts/build-textures.sh        # 256x256
#   scripts/build-textures.sh 512    # 512x512
#
# Requires ImageMagick (`brew install imagemagick`); SVG sources also need
# librsvg (`brew install librsvg`, provides rsvg-convert).

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

# Vector sources -> PNG. Skipped (with a warning) if there are none or no rasterizer.
svgs=("$ASSETS_DIR"/*.svg)
if [ ${#svgs[@]} -gt 0 ]; then
  if command -v rsvg-convert >/dev/null 2>&1; then
    for svg in "${svgs[@]}"; do
      png="${svg%.svg}.png"
      rsvg-convert -w "$SIZE" -h "$SIZE" "$svg" -o "$png"
      echo "  $(basename "$svg") -> $(basename "$png")  (${SIZE}x${SIZE})"
    done
  else
    echo "rsvg-convert not found; skipping SVG sources. Install it with: brew install librsvg" >&2
  fi
fi

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
