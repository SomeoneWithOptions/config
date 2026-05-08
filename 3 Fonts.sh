#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT_DIR="$SCRIPT_DIR/fonts/azaret"
OTF_DIR="$FONT_DIR/otf"
TTF_DIR="$FONT_DIR/ttf"
VARIABLE_DIR="$FONT_DIR/variable"
FONTS_CHANGED=0

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

OS="$(uname)"
INSTALL_DIR=""

case "$OS" in
  Linux)
    INSTALL_DIR="$HOME/.local/share/fonts"
    copy_fonts "$OTF_DIR" "$INSTALL_DIR"
    copy_fonts "$TTF_DIR" "$INSTALL_DIR"
    copy_fonts "$VARIABLE_DIR" "$INSTALL_DIR"
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
    copy_fonts "$OTF_DIR" "$INSTALL_DIR"
    copy_fonts "$TTF_DIR" "$INSTALL_DIR"
    copy_fonts "$VARIABLE_DIR" "$INSTALL_DIR"
    ;;
  *)
    echo "Unsupported operating system: $OS"
    exit 1
    ;;
esac

if command -v omarchy-font-set >/dev/null 2>&1; then
  if command -v omarchy-font-current >/dev/null 2>&1; then
    CURRENT_FONT="$(omarchy-font-current 2>/dev/null || true)"
    if [ "$CURRENT_FONT" != "Azeret Mono" ]; then
      omarchy-font-set "Azeret Mono"
    fi
  elif [ "$FONTS_CHANGED" -eq 1 ]; then
    omarchy-font-set "Azeret Mono"
  fi
fi

echo "Fonts installed to $INSTALL_DIR"
