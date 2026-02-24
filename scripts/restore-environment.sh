#!/usr/bin/env bash
# Restore dev environment from config/installed-tools.json and config/profiles/.
# Fail-safe: each step skips if already present or on install failure.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/config"
PROFILES="$CONFIG/profiles"
JSON="$CONFIG/installed-tools.json"

log() { printf '[restore] %s\n' "$*" >&2; }
skip() { log "Skip (already ok or failed): $*"; }
json_get() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k] // empty' "$JSON" 2>/dev/null; else grep -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$JSON" 2>/dev/null | sed -n 's/.*:[[:space:]]*"\([^"]*\)".*/\1/p'; fi; }
json_array() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k][]? // empty' "$JSON" 2>/dev/null; else sed -n "/\"$k\"[[:space:]]*:/,/\]/p" "$JSON" | grep -o '"[^"]*"' | tr -d '"'; fi; }

[ -f "$JSON" ] || { log "Missing $JSON. Run collect-tools.sh on the source machine first."; exit 1; }

# --- APT packages (top-level list; may need sudo) ---
install_apt_packages() {
  local list="$CONFIG/apt-packages.txt"
  [ -f "$list" ] || return 0
  command -v apt-get &>/dev/null || { log "apt-get not found; skip APT packages."; return 0; }
  while IFS= read -r pkg _; do
    [ -z "$pkg" ] && continue
    [[ "$pkg" =~ ^#.* ]] && continue
    dpkg -l "$pkg" &>/dev/null && continue
    log "Installing APT package: $pkg"
    sudo apt-get install -y "$pkg" 2>/dev/null || true
  done < "$list"
}
install_apt_packages || true

# --- uv (Python) ---
install_uv() {
  if command -v uv &>/dev/null; then skip "uv"; return 0; fi
  log "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh || true
  export PATH="${HOME}/.local/bin:${PATH}"
}
install_uv || true

# --- SDKMAN + Java ---
install_sdkman_java() {
  if command -v java &>/dev/null && command -v sdk &>/dev/null; then skip "SDKMAN/Java"; return 0; fi
  if ! command -v sdk &>/dev/null; then
    log "Installing SDKMAN..."
    (curl -s "https://get.sdkman.io" | bash) || true
    export SDKMAN_DIR="${HOME}/.sdkman" && [ -f "${HOME}/.sdkman/bin/sdkman-init.sh" ] && . "${HOME}/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
  fi
  command -v sdk &>/dev/null || return 0
  local want
  want=$(json_get "java_version")
  # Prefer SDKMAN id (e.g. 21.0.8-tem); else parse openjdk version string
  if [[ "$want" == *"tem"* ]] && [[ "$want" == *"21"* ]]; then
    want="21.0.8-tem"
  elif [ -n "$want" ] && [[ "$want" != *"version"* ]]; then
    want=$(echo "$want" | tr -d '[:space:]')
  else
    want="21.0.8-tem"
  fi
  [ -z "$want" ] && want="21.0.8-tem"
  log "Installing Java ($want)..."
  sdk install java "$want" 2>/dev/null || sdk install java 21.0.8-tem 2>/dev/null || true
}
install_sdkman_java || true

# --- Rust ---
install_rust() {
  if command -v rustc &>/dev/null; then skip "Rust"; return 0; fi
  log "Installing Rust (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y -q 2>/dev/null || true
  [ -f "${HOME}/.cargo/env" ] && . "${HOME}/.cargo/env" 2>/dev/null || true
}
install_rust || true

# --- Node (fnm) + npm globals ---
install_node() {
  if command -v fnm &>/dev/null; then
    if command -v node &>/dev/null; then skip "Node (fnm)"; return 0; fi
  fi
  if ! command -v fnm &>/dev/null; then
    log "Installing fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash 2>/dev/null || true
    export PATH="${HOME}/.local/share/fnm:${PATH}"
    eval "$(fnm env 2>/dev/null)" || true
  fi
  command -v fnm &>/dev/null || return 0
  local v
  v=$(json_get "node_version")
  v=${v#v}
  if [ -n "$v" ]; then
    log "Installing Node $v..."
    fnm install "$v" 2>/dev/null || fnm install --lts 2>/dev/null || true
    fnm use "$v" 2>/dev/null || fnm default "$v" 2>/dev/null || true
  else
    fnm install --lts 2>/dev/null || true
  fi
  eval "$(fnm env 2>/dev/null)" || true
  # npm global packages
  while read -r pkg; do
    [ -z "$pkg" ] && continue
    command -v npm &>/dev/null || continue
    npm list -g "$pkg" &>/dev/null && continue
    log "Installing npm global: $pkg"
    npm install -g "$pkg" 2>/dev/null || true
  done < <(json_array "npm_global_packages")
}
install_node || true

# --- Docker ---
install_docker() {
  if command -v docker &>/dev/null; then skip "Docker"; return 0; fi
  log "Installing Docker (may need sudo)..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq 2>/dev/null; sudo apt-get install -y docker.io 2>/dev/null || true
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y docker 2>/dev/null || true
  else
    curl -fsSL https://get.docker.com | sh 2>/dev/null || true
  fi
}
install_docker || true

# --- Podman ---
install_podman() {
  if command -v podman &>/dev/null; then skip "Podman"; return 0; fi
  log "Installing Podman (may need sudo)..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq 2>/dev/null; sudo apt-get install -y podman 2>/dev/null || true
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y podman 2>/dev/null || true
  fi
}
install_podman || true

# --- kubectl ---
install_kubectl() {
  if command -v kubectl &>/dev/null; then skip "kubectl"; return 0; fi
  log "Installing kubectl..."
  local tmp
  tmp=$(mktemp)
  curl -sSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o "$tmp" 2>/dev/null && chmod +x "$tmp" && (sudo mv "$tmp" /usr/local/bin/kubectl 2>/dev/null || mv "$tmp" "$HOME/.local/bin/kubectl" 2>/dev/null) || rm -f "$tmp"
}
install_kubectl || true

# --- VSCode extensions + profile ---
apply_vscode() {
  command -v code &>/dev/null || { log "VSCode (code) not in PATH; skip extensions/profile"; return 0; }
  while read -r ext; do
    [ -z "$ext" ] && continue
    code --list-extensions 2>/dev/null | grep -qxF "$ext" && continue
    log "Installing VSCode extension: $ext"
    code --install-extension "$ext" 2>/dev/null || true
  done < <(json_array "vscode_extensions")
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
  [ -d "$PROFILES/vscode" ] || return 0
  mkdir -p "$dest"
  [ -f "$PROFILES/vscode/settings.json" ] && cp "$PROFILES/vscode/settings.json" "$dest/" 2>/dev/null || true
  [ -f "$PROFILES/vscode/keybindings.json" ] && cp "$PROFILES/vscode/keybindings.json" "$dest/" 2>/dev/null || true
  [ -d "$PROFILES/vscode/snippets" ] && cp -r "$PROFILES/vscode/snippets" "$dest/" 2>/dev/null || true
  [ -f "$PROFILES/vscode/profiles.json" ] && cp "$PROFILES/vscode/profiles.json" "$dest/" 2>/dev/null || true
  log "VSCode profile applied."
}
apply_vscode || true

# --- Cursor extensions + profile ---
apply_cursor() {
  command -v cursor &>/dev/null || { log "Cursor not in PATH; skip extensions/profile"; return 0; }
  while read -r ext; do
    [ -z "$ext" ] && continue
    cursor --list-extensions 2>/dev/null | grep -qxF "$ext" && continue
    log "Installing Cursor extension: $ext"
    cursor --install-extension "$ext" 2>/dev/null || true
  done < <(json_array "cursor_extensions")
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User"
  [ -d "$PROFILES/cursor" ] || return 0
  mkdir -p "$dest"
  [ -f "$PROFILES/cursor/settings.json" ] && cp "$PROFILES/cursor/settings.json" "$dest/" 2>/dev/null || true
  [ -f "$PROFILES/cursor/keybindings.json" ] && cp "$PROFILES/cursor/keybindings.json" "$dest/" 2>/dev/null || true
  [ -d "$PROFILES/cursor/snippets" ] && cp -r "$PROFILES/cursor/snippets" "$dest/" 2>/dev/null || true
  log "Cursor profile applied."
}
apply_cursor || true

# --- OS / shell / config (from collect-os-and-shell.sh) ---
apply_os_shell() {
  local dest_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  # Shell dotfiles
  for f in .bashrc .profile .bash_logout .inputrc; do
    [ -f "$CONFIG/shell/$f" ] && cp "$CONFIG/shell/$f" "$HOME/$f" 2>/dev/null && log "Restored $f" || true
  done
  [ -d "$CONFIG/shell/fish" ] && cp -r "$CONFIG/shell/fish" "$dest_config/" 2>/dev/null && log "Restored fish config" || true
  # Bash history: append (skip comment lines) so we don't overwrite target history
  if [ -f "$CONFIG/shell/bash_history" ]; then
    grep -v '^#' "$CONFIG/shell/bash_history" 2>/dev/null | grep -v '^$' | tail -n 5000 >> "$HOME/.bash_history" 2>/dev/null && log "Appended bash_history" || true
  fi
  # Git
  [ -f "$CONFIG/git/gitconfig" ] && cp "$CONFIG/git/gitconfig" "$HOME/.gitconfig" 2>/dev/null && log "Restored .gitconfig" || true
  [ -d "$CONFIG/git/config.d" ] && mkdir -p "$dest_config/git" && cp -r "$CONFIG/git/config.d"/* "$dest_config/git/" 2>/dev/null && log "Restored git config.d" || true
  # SSH config (no keys)
  [ -f "$CONFIG/ssh/config" ] && mkdir -p "$HOME/.ssh" && cp "$CONFIG/ssh/config" "$HOME/.ssh/config" 2>/dev/null && log "Restored .ssh/config" || true
  # Default apps and autostart
  [ -f "$CONFIG/os/mimeapps.list" ] && cp "$CONFIG/os/mimeapps.list" "$dest_config/mimeapps.list" 2>/dev/null && log "Restored mimeapps.list" || true
  if [ -d "$CONFIG/os/autostart" ]; then
    mkdir -p "$dest_config/autostart"
    for f in "$CONFIG/os/autostart"/*.desktop; do [ -f "$f" ] && cp "$f" "$dest_config/autostart/" 2>/dev/null; done
    log "Restored autostart"
fi
  # MCP
  [ -f "$CONFIG/mcp/vscode-mcp.json" ] && mkdir -p "$dest_config/Code/User" && cp "$CONFIG/mcp/vscode-mcp.json" "$dest_config/Code/User/mcp.json" 2>/dev/null && log "Restored Code mcp.json" || true
  [ -f "$CONFIG/mcp/cursor-mcp.json" ] && mkdir -p "$HOME/.cursor" && cp "$CONFIG/mcp/cursor-mcp.json" "$HOME/.cursor/mcp.json" 2>/dev/null && log "Restored Cursor mcp.json" || true
  # Dconf (optional; use with care — can override existing desktop settings)
  if [ -f "$CONFIG/os/dconf-dump.txt" ] && command -v dconf &>/dev/null; then
    log "dconf-dump.txt present; to restore desktop settings run: dconf load / < $CONFIG/os/dconf-dump.txt (review first)"
  fi
}
apply_os_shell || true

log "Restore finished. Re-run if you need to retry failed steps."
