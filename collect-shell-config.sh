#!/usr/bin/env bash
# Collect/bash backup shell config files from $HOME to a destination directory.
# Universal script: no OS-specific logic. Run on any Linux/Unix.
#
# Usage:
#   ./collect-shell-config.sh [DEST]
#   CONFIG=/path/to/config ./collect-shell-config.sh
#
# DEST defaults to: $CONFIG/shell (if CONFIG set) or $(dirname $0)/config/shell

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CONFIG:-$ROOT/config}"
DEST="${1:-$CONFIG/shell}"

log() { printf '[collect-shell] %s\n' "$*" >&2; }

mkdir -p "$DEST" 2>/dev/null || { log "Cannot create $DEST"; exit 1; }

for f in .bashrc .profile .bash_logout .inputrc; do
  if [ -f "$HOME/$f" ]; then
    cp "$HOME/$f" "$DEST/$f" 2>/dev/null && log "Collected $f" || log "Failed to copy $f"
  else
    log "Skipped $f (not found)"
  fi
done

if [ -f "$HOME/.bash_history" ]; then
  cp "$HOME/.bash_history" "$DEST/bash_history" 2>/dev/null && log "Collected bash_history" || log "Failed to copy .bash_history"
else
  log "Skipped .bash_history (not found)"
fi

dc="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -d "$dc/fish" ]; then
  cp -r "$dc/fish" "$DEST/" 2>/dev/null && log "Collected fish/" || log "Failed to copy fish/"
else
  log "Skipped fish/ (not found)"
fi

log "Done. Shell config saved to $DEST"
