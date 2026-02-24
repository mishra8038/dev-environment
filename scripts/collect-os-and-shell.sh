#!/usr/bin/env bash
# Collect OS customizations, shell config, bash history, and related dotfiles
# into config/shell/, config/os/, config/git/, config/ssh/, config/mcp/.
# Fail-safe: missing files are skipped. Bash history may contain secrets — review before committing.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config"
HOME="${HOME:-$HOME}"

log() { printf '%s\n' "$*" >&2; }
copy_safe() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    if cp "$src" "$dst" 2>/dev/null; then
      log "Copied $src -> $dst"
    else
      log "Skip (copy failed): $src"
    fi
  else
    log "Skip (missing): $src"
  fi
}

# --- Shell: .bashrc, .profile, .bash_logout, .inputrc ---
for f in .bashrc .profile .bash_logout .inputrc; do
  [ -f "$HOME/$f" ] && copy_safe "$HOME/$f" "$CONFIG/shell/$f"
done
if [ -d "$HOME/.config/fish" ]; then
  mkdir -p "$CONFIG/shell" && cp -r "$HOME/.config/fish" "$CONFIG/shell/" 2>/dev/null && log "Copied .config/fish -> config/shell/fish" || log "Skip (copy failed): .config/fish"
fi

# --- Bash history (may contain secrets; review before committing) ---
if [ -f "$HOME/.bash_history" ]; then
  mkdir -p "$CONFIG/shell"
  {
    echo "# Bash history from source machine. May contain secrets — review before committing or sharing."
    echo "# Restore: append to ~/.bash_history or replace. Restore script can merge."
    echo ""
    cat "$HOME/.bash_history"
  } > "$CONFIG/shell/bash_history"
  log "Copied .bash_history -> config/shell/bash_history (review for secrets)."
fi

# --- Git ---
[ -f "$HOME/.gitconfig" ] && copy_safe "$HOME/.gitconfig" "$CONFIG/git/gitconfig"
[ -d "$HOME/.config/git" ] && copy_safe "$HOME/.config/git" "$CONFIG/git/config.d"

# --- SSH config only (no keys) ---
if [ -f "$HOME/.ssh/config" ]; then
  mkdir -p "$CONFIG/ssh"
  cp "$HOME/.ssh/config" "$CONFIG/ssh/config" 2>/dev/null && log "Copied .ssh/config (no keys)." || log "Skip: .ssh/config"
fi

# --- Default apps and autostart ---
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" ] && copy_safe "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" "$CONFIG/os/mimeapps.list"
if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/autostart" ]; then
  for f in "${XDG_CONFIG_HOME:-$HOME/.config}/autostart"/*.desktop; do
    [ -f "$f" ] && copy_safe "$f" "$CONFIG/os/autostart/$(basename "$f")"
  done
fi

# --- MCP (Cursor / Code) ---
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/mcp.json" ] && copy_safe "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/mcp.json" "$CONFIG/mcp/vscode-mcp.json"
[ -f "$HOME/.cursor/mcp.json" ] && copy_safe "$HOME/.cursor/mcp.json" "$CONFIG/mcp/cursor-mcp.json"

# --- APT sources.list.d: list of repo filenames (for reference; actual restore may need manual add) ---
if [ -d /etc/apt/sources.list.d ] && [ -r /etc/apt/sources.list.d ]; then
  ls -1 /etc/apt/sources.list.d 2>/dev/null | grep -v '\.disabled$' > "$CONFIG/os/apt-sources-list.d.txt" 2>/dev/null && \
    log "Wrote config/os/apt-sources-list.d.txt (list of repo files; restore repos manually if needed)." || true
fi

# --- GSettings / dconf: optional dump of common desktop customizations ---
dump_dconf() {
  local out="$CONFIG/os/dconf-dump.txt"
  mkdir -p "$(dirname "$out")"
  {
    echo "# Dconf dump (desktop/panel/keyboard customizations). Restore with: dconf load / < this file (use with care)."
    echo "# Generated: $(date -Iseconds 2>/dev/null || date)"
    echo ""
  } > "$out"
  # Only dump common customization paths (avoid huge system dumps)
  for path in /org/cinnamon /org/gnome/terminal /org/gnome/desktop/window-keybindings /org/gnome/desktop/input-sources; do
    if dconf dump "$path" 2>/dev/null | head -1 | grep -q '^\['; then
      echo "[$path]" >> "$out"
      dconf dump "$path" 2>/dev/null | tail -n +2 >> "$out"
      echo "" >> "$out"
    fi
  done
  [ -s "$out" ] && log "Wrote $out (dconf dump)." || rm -f "$out"
}
command -v dconf &>/dev/null && dump_dconf || true

# --- Optional: Autokey, variety, etc. (uncomment if you use them) ---
# [ -d "$HOME/.config/autokey" ] && copy_safe "$HOME/.config/autokey" "$CONFIG/os/autokey"
# [ -d "$HOME/.config/variety" ] && copy_safe "$HOME/.config/variety" "$CONFIG/os/variety"

log "OS/shell/config collect done. Review config/shell/bash_history and config/ssh before committing."
