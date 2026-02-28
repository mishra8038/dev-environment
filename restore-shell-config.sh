#!/usr/bin/env bash
# Restore shell config files from a source directory to $HOME.
# Universal script: no OS-specific logic. Run on any Linux/Unix.
#
# Usage:
#   ./restore-shell-config.sh [SOURCE]
#   CONFIG=/path/to/config ./restore-shell-config.sh
#
# SOURCE defaults to: $CONFIG/shell (if CONFIG set) or $(dirname $0)/config/shell

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CONFIG:-$ROOT/config}"
SOURCE="${1:-$CONFIG/shell}"

log() { printf '[restore-shell] %s\n' "$*" >&2; }
skip() { log "Skip: $*"; }

[ -d "$SOURCE" ] || { log "Source directory not found: $SOURCE"; exit 1; }

# Backup existing .bashrc before overwriting (one-time)
if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.bashrc.restore-default" ]; then
  cp "$HOME/.bashrc" "$HOME/.bashrc.restore-default" 2>/dev/null && log "Backed up .bashrc to .bashrc.restore-default" || true
fi

for f in .bashrc .profile .bash_logout .inputrc; do
  if [ -f "$SOURCE/$f" ]; then
    cp "$SOURCE/$f" "$HOME/$f" 2>/dev/null && log "Restored $f" || log "Failed to restore $f"
  else
    skip "$f (not in source)"
  fi
done

dc="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -d "$SOURCE/fish" ]; then
  mkdir -p "$dc" 2>/dev/null || true
  cp -r "$SOURCE/fish" "$dc/" 2>/dev/null && log "Restored fish/" || log "Failed to restore fish/"
else
  skip "fish/ (not in source)"
fi

if [ -f "$SOURCE/bash_history" ] && [ ! -f "$HOME/.restore_bash_history_done" ]; then
  grep -v '^#' "$SOURCE/bash_history" 2>/dev/null | grep -v '^$' | tail -n 5000 >> "$HOME/.bash_history" 2>/dev/null || true
  touch "$HOME/.restore_bash_history_done" 2>/dev/null || true
  log "Appended bash_history"
else
  [ -f "$HOME/.restore_bash_history_done" ] && skip "bash_history (already appended)"
fi

log "Done. Shell config restored from $SOURCE"
