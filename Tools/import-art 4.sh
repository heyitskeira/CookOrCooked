#!/bin/bash
#
# import-art.sh — file Figma PNG exports into Cooked's asset catalog.
#
# Drop correctly-named PNGs into Assets-agung/drop, run this, commit.
# Naming and export settings: Docs/ArtPipeline.md
#
# Usage:
#   Tools/import-art.sh              # import everything in the drop folder
#   Tools/import-art.sh --dry-run    # show what would happen, touch nothing
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROP="$ROOT/Assets-agung/drop"
CATALOG="$ROOT/Cooked/Assets.xcassets"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

# Where each name prefix lands. Sprite atlases batch their draw calls, so
# anything SpriteKit renders every frame goes in one. Anything SwiftUI shows
# (the inventory bar, storage, popups) must NOT be in an atlas — UIImage and
# SwiftUI's Image cannot see inside a .spriteatlas, only SKTexture can.
destination_for() {
  case "$1" in
    station-*|floor-*|wall-*|prop-*|shadow-*) echo "Kitchen.spriteatlas" ;;
    chef-*)                                   echo "Chefs.spriteatlas"   ;;
    food-*|utensil-*|ui-*)                    echo ""                    ;;  # catalog root
    *)                                        echo "?"                   ;;
  esac
}

write_atlas_contents() {
  local dir="$1"
  [[ -f "$dir/Contents.json" ]] && return
  cat > "$dir/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : false }
}
JSON
}

# Rebuilds an imageset's Contents.json from whichever @2x/@3x files are present,
# so re-running after adding a missing scale just works.
write_imageset_contents() {
  local dir="$1" name="$2"
  local entries=()
  for scale in 1 2 3; do
    if [[ -f "$dir/${name}@${scale}x.png" ]]; then
      entries+=("    { \"filename\" : \"${name}@${scale}x.png\", \"idiom\" : \"universal\", \"scale\" : \"${scale}x\" }")
    else
      entries+=("    { \"idiom\" : \"universal\", \"scale\" : \"${scale}x\" }")
    fi
  done
  {
    echo '{'
    echo '  "images" : ['
    printf '%s,\n' "${entries[0]}" "${entries[1]}"
    printf '%s\n'  "${entries[2]}"
    echo '  ],'
    echo '  "info" : { "author" : "xcode", "version" : 1 }'
    echo '}'
  } > "$dir/Contents.json"
}

# Recursive, and null-delimited so spaces in folder or file names survive.
# Figma exports often arrive inside a subfolder, and its default filenames are
# full of spaces, so neither can be treated as a mistake.
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
  find "$DROP" -type f \( -iname '*.png' \) -print0 | sort -z
)
if (( ${#files[@]} == 0 )); then
  echo "Nothing in $DROP — export from Figma first (see Docs/ArtPipeline.md)."
  exit 0
fi

imported=0; skipped=0
for f in "${files[@]}"; do
  base="$(basename "$f" .png)"; base="${base%.PNG}"

  # Split "name@3x" into name + scale. A bare name is assumed to be @3x,
  # which is what Figma gives you if you forget to set the suffix.
  # Figma's suffix box is free text, so the separator that ends up in front of
  # the scale varies with whoever set the export up — "@2x", "-@2x", "-2x",
  # "_2x". They all mean the same thing, so all of them are accepted.
  if [[ "$base" =~ ^(.+[^-_@])[-_]?@?([123])x$ ]]; then
    name="${BASH_REMATCH[1]}"; scale="${BASH_REMATCH[2]}"
  else
    name="$base"; scale=3
    echo "  note: '$base.png' has no @Nx suffix — filing as @3x"
  fi

  dest="$(destination_for "$name")"
  if [[ "$dest" == "?" ]]; then
    # Suggest the name this file probably wants, so the fix is a rename in
    # Figma rather than a trip back to the docs.
    slug="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\{1,\}/-/g; s/^-//; s/-$//')"
    echo "  SKIP '$base.png' — name has no known prefix."
    echo "       Rename the Figma frame to one of:"
    echo "         ui-$slug          (a screen or button — SwiftUI can see it)"
    echo "         prop-$slug        (scenery inside the kitchen)"
    echo "       Full list of prefixes and names: Docs/ArtPipeline.md"
    skipped=$((skipped+1)); continue
  fi

  target_dir="$CATALOG${dest:+/$dest}/${name}.imageset"
  echo "  $base.png  ->  ${dest:-<root>}/${name}.imageset/${name}@${scale}x.png"
  if (( DRY == 0 )); then
    [[ -n "$dest" ]] && mkdir -p "$CATALOG/$dest" && write_atlas_contents "$CATALOG/$dest"
    mkdir -p "$target_dir"
    mv "$f" "$target_dir/${name}@${scale}x.png"
    write_imageset_contents "$target_dir" "$name"
  fi
  imported=$((imported+1))
done

echo
if (( DRY == 1 )); then
  echo "Dry run — nothing moved. $imported would import, $skipped skipped."
else
  echo "Imported $imported, skipped $skipped. Now build, then commit Cooked/Assets.xcassets."
fi
