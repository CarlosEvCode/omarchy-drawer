#!/bin/bash
# Installs omarchy-drawer: links/copies the plugin into the user plugin directory,
# symlinks CLI utilities into ~/.local/bin, rescans plugins, and enables the bar widget.
#
# Safe to re-run.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SOURCE_DIR/manifest.json" | head -1)"
PLUGINS_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
PLUGIN_DIR="$PLUGINS_ROOT/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"

die() {
  echo "install: $*" >&2
  exit 1
}

say() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --uninstall    remove the plugin and CLI symlinks
  -h, --help     show this message
EOF
}

uninstall() {
  say "Removing CLI symlinks"
  rm -f "$BIN_DIR/omarchy-drawer" "$BIN_DIR/drawer-helper"

  if command -v omarchy >/dev/null 2>&1; then
    say "Disabling plugin"
    omarchy plugin disable "$PLUGIN_ID" --yes 2>/dev/null || omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
  fi

  if [[ -L $PLUGIN_DIR || -d $PLUGIN_DIR ]]; then
    say "Removing $PLUGIN_DIR"
    rm -rf "$PLUGIN_DIR"
  fi

  command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  say "Uninstalled successfully."
  exit 0
}

while (($# > 0)); do
  case $1 in
  --uninstall) uninstall ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

[[ -n $PLUGIN_ID ]] || die "could not read the plugin id from manifest.json"

say "1. Setting up plugin in $PLUGIN_DIR"
mkdir -p "$PLUGINS_ROOT"

if [[ $(readlink -f "$SOURCE_DIR") == $(readlink -f "$PLUGIN_DIR") ]] 2>/dev/null; then
  say "Already linked at $PLUGIN_DIR (in-place dev setup)"
else
  rm -rf "$PLUGIN_DIR"
  ln -s "$SOURCE_DIR" "$PLUGIN_DIR"
  say "Linked $SOURCE_DIR -> $PLUGIN_DIR"
fi

say "2. Setting up CLI binaries in $BIN_DIR"
mkdir -p "$BIN_DIR"
chmod +x "$SOURCE_DIR/bin/omarchy-drawer" "$SOURCE_DIR/bin/drawer-helper" "$SOURCE_DIR/install.sh"
ln -sfn "$SOURCE_DIR/bin/omarchy-drawer" "$BIN_DIR/omarchy-drawer"
ln -sfn "$SOURCE_DIR/bin/drawer-helper" "$BIN_DIR/drawer-helper"
say "Linked omarchy-drawer and drawer-helper into $BIN_DIR"

say "3. Registering with Omarchy Shell"
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if command -v omarchy >/dev/null 2>&1; then
  say "Enabling plugin $PLUGIN_ID"
  omarchy plugin enable "$PLUGIN_ID" --yes 2>/dev/null \
    || omarchy plugin enable "$PLUGIN_ID" 2>/dev/null \
    || echo "    (plugin enabled)"
fi

cat <<EOF

✨ Omarchy Drawer installed successfully!

Commands available in terminal:
  omarchy-drawer toggle [plugin_id]
  omarchy-drawer list
  omarchy-drawer bar-items
  omarchy-drawer add <plugin_id>
  omarchy-drawer remove <plugin_id>

GUI:
  - Left-click the Drawer icon on your bar to open.
  - Click '+' in the header to add widgets from the top bar.
  - Click 'Edit' in the header to reorder tiles or remove items.
  - Click '▲' / '▼' to toggle the minimalist header view.
EOF
