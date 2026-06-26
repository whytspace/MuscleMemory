#!/usr/bin/env bash
#
# Turn `/mm shot tour` captures into named transparent images for the README.
#
# The tour fires a black+white screenshot pair for each view in a fixed order,
# and WoW names screenshots by timestamp, so this relies on order: it takes the
# newest 2*N screenshots, recovers true alpha from each black/white pair
# (difference matting), trims to the content, and writes one named PNG per view.
#
# Usage:
#   scripts/process-shots.sh                 # all tour views, in order
#   scripts/process-shots.sh macro-window    # just the newest pair
#   SHOTS_DIR=/path scripts/process-shots.sh
#
# Requires: ImageMagick 7 (`magick`) — brew install imagemagick

set -euo pipefail

SHOTS_DIR="${SHOTS_DIR:-/Applications/Games/World of Warcraft/_retail_/Screenshots}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/images"

# Output names, in the exact order the tour captures them.
if [ "$#" -gt 0 ]; then
  views=("$@")
else
  views=(layers dynamic-actions macro-editor macro-window profiles)
fi

command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick not found — install it with: brew install imagemagick" >&2
  exit 1
}
[ -d "$SHOTS_DIR" ] || {
  echo "screenshots folder not found: $SHOTS_DIR" >&2
  exit 1
}
mkdir -p "$OUT_DIR"

# Difference matte: alpha = 1 - (white - black); colour = black / alpha (un-
# premultiplied), then trim the surrounding transparency.
matte() { # black white out
  magick \
    \( "$1" "$2" -compose Mathematics -define compose:args=0,-1,1,1 -composite \) -write mpr:alpha +delete \
    "$1" mpr:alpha -compose Divide -composite \
    mpr:alpha -alpha off -compose CopyOpacity -composite \
    -trim +repage "$3"
}

# Newest 2*N screenshots, oldest-first (matching capture order).
need=$((2 * ${#views[@]}))
recent=()
while IFS= read -r f; do recent+=("$f"); done < <(ls -t "$SHOTS_DIR"/*.png 2>/dev/null | head -n "$need" | tail -r)

if [ "${#recent[@]}" -lt "$need" ]; then
  echo "need $need screenshots (${#views[@]} views x black+white), found ${#recent[@]} in $SHOTS_DIR" >&2
  exit 1
fi

for i in "${!views[@]}"; do
  black="${recent[$((2 * i))]}"
  white="${recent[$((2 * i + 1))]}"
  out="$OUT_DIR/${views[$i]}.png"
  matte "$black" "$white" "$out"
  echo "$(basename "$out")  <-  $(basename "$black") + $(basename "$white")"
done
