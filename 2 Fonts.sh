#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT_ROOT="$SCRIPT_DIR/fonts"
FONTS_CHANGED=0
OMARCHY_FONT="DM Sans"

copy_fonts() {
  local source_dir="$1"
  local install_dir="$2"
  local font_path dest_path
  local files=()

  if [ ! -d "$source_dir" ]; then
    return
  fi

  # Collect font files without relying on non-portable find(1) options like -maxdepth.
  shopt -s nullglob
  files=("$source_dir"/*.otf "$source_dir"/*.ttf)
  shopt -u nullglob

  if [ "${#files[@]}" -eq 0 ]; then
    return
  fi

  mkdir -p "$install_dir"

  for font_path in "${files[@]}"; do
    dest_path="$install_dir/$(basename "$font_path")"
    if [ ! -f "$dest_path" ] || ! cmp -s "$font_path" "$dest_path"; then
      cp -f "$font_path" "$dest_path"
      printf 'Installed %s\n' "$dest_path"
      FONTS_CHANGED=1
    fi
  done
}

install_font_set() {
  local install_dir="$1"

  copy_fonts "$FONT_ROOT/azaret/otf" "$install_dir"
  copy_fonts "$FONT_ROOT/azaret/ttf" "$install_dir"
  copy_fonts "$FONT_ROOT/azaret/variable" "$install_dir"
  copy_fonts "$FONT_ROOT/dm-sans" "$install_dir"
  copy_fonts "$FONT_ROOT/dejavu" "$install_dir"
}

OS="$(uname)"
INSTALL_DIR=""

case "$OS" in
  Linux)
    INSTALL_DIR="$HOME/.local/share/fonts"
    install_font_set "$INSTALL_DIR"
    if [ "$FONTS_CHANGED" -eq 1 ]; then
      if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -fv "$INSTALL_DIR"
      else
        echo "fc-cache not found. Please install fontconfig to refresh the font cache."
      fi
    fi
    ;;
  Darwin)
    INSTALL_DIR="$HOME/Library/Fonts"
    install_font_set "$INSTALL_DIR"
    ;;
  *)
    echo "Unsupported operating system for font installation: $OS; skipping."
    exit 0
    ;;
esac

if command -v omarchy-font-set >/dev/null 2>&1; then
  if command -v omarchy-font-current >/dev/null 2>&1; then
    CURRENT_FONT="$(omarchy-font-current 2>/dev/null || true)"
    if [ "$CURRENT_FONT" != "$OMARCHY_FONT" ]; then
      omarchy-font-set "$OMARCHY_FONT"
    fi
  elif [ "$FONTS_CHANGED" -eq 1 ]; then
    omarchy-font-set "$OMARCHY_FONT"
  fi
fi

echo "Fonts installed to $INSTALL_DIR"
