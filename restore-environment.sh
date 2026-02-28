#!/usr/bin/env bash
# Restore dev environment. SCP this file + config/ to Ubuntu Server, then run: ./restore-environment.sh
# Idempotent: skips tools already installed; safe to re-run.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/config"
JSON="$CONFIG/installed-tools.json"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

# Set to 'true' to auto-accept the Microsoft core fonts EULA for ttf-mscorefonts-installer.
# Change to 'false' if you prefer to skip automatic EULA acceptance and install that package manually.
export RESTORE_ACCEPT_MS_EULA=${RESTORE_ACCEPT_MS_EULA:-true}

RESULTS="$ROOT/results"
mkdir -p "$RESULTS" 2>/dev/null || true
LOG_FILE="$RESULTS/restore-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[restore] %s\n' "$*" >&2; }
skip() { log "Skip: $*"; }
json_get() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k] // empty' "$JSON" 2>/dev/null; else grep -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$JSON" 2>/dev/null | sed -n 's/.*:[[:space:]]*"\([^"]*\)".*/\1/p'; fi; }
json_array() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k][]? // empty' "$JSON" 2>/dev/null; else sed -n "/\"$k\"[[:space:]]*:/,/\]/p" "$JSON" | grep -o '"[^"]*"' | tr -d '"'; fi; }

[ -f "$JSON" ] || { log "Missing $JSON. Put config/ next to this script (config/installed-tools.json, etc.)."; exit 1; }

RESTORE_GROUPS=(prerequisites python java rust node containers vscode_install cursor_install chrome_install jetbrains_toolbox editors config fonts flatpak claude_code)
DEFAULT_SEL=(1 1 1 1 1 1 0 0 0 0 1 0 0 0 0)

DEV_GROUPS=(general dev java cpp rust js python kubernetes fonts jetbrains cursor)
DEV_DEFAULT_SEL=(1 1 1 1 1 1 1 1 0 0 0 0)

run_prerequisites() {
  command -v apt-get &>/dev/null || return 0
  for p in unzip curl; do command -v "$p" &>/dev/null || { log "Installing unzip curl ca-certificates (sudo)"; sudo apt-get update -qq 2>/dev/null; sudo apt-get install -y unzip curl ca-certificates 2>/dev/null || true; return 0; }; done
  if command -v apt-get &>/dev/null; then
    # Core dev/desktop packages
    for p in build-essential git cinnamon-core systemd-sysv util-linux; do
      dpkg -l "$p" &>/dev/null && continue
      log "Installing $p (sudo)"
      sudo apt-get install -y "$p" 2>/dev/null || true
    done
    # Secret Service / keyring support for VSCode, Cursor, JetBrains, etc.
    for p in gnome-keyring seahorse libsecret-1-0 libsecret-tools; do
      dpkg -l "$p" &>/dev/null && continue
      log "Installing $p (sudo)"
      sudo apt-get install -y "$p" 2>/dev/null || true
    done
  fi
  skip "Prerequisites (unzip, curl, ca-certificates, build-essential, git, cinnamon-core, systemd-sysv, util-linux, gnome-keyring, libsecret)"
}

run_python() {
  command -v uv &>/dev/null && { skip "uv"; return 0; }
  log "Installing uv"; curl -LsSf https://astral.sh/uv/install.sh | sh || true
  export PATH="${HOME}/.local/bin:${PATH}"
}

run_java() {
  command -v java &>/dev/null && command -v sdk &>/dev/null && { skip "Java"; return 0; }
  command -v sdk &>/dev/null || { log "Installing SDKMAN"; curl -s "https://get.sdkman.io" | bash || true; export SDKMAN_DIR="${HOME}/.sdkman"; [ -f "${HOME}/.sdkman/bin/sdkman-init.sh" ] && . "${HOME}/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true; }
  command -v sdk &>/dev/null || return 0
  local w=$(json_get "java_version"); [[ "$w" == *tem* && "$w" == *21* ]] && w="21.0.8-tem" || w="${w:-21.0.8-tem}"; w=$(echo "$w" | tr -d '[:space:]'); [ -z "$w" ] && w="21.0.8-tem"
  log "Installing Java $w"; sdk install java "$w" 2>/dev/null || sdk install java 21.0.8-tem 2>/dev/null || true
  if command -v apt-get &>/dev/null; then
    for p in maven gradle; do
      dpkg -l "$p" &>/dev/null && continue
      log "Installing $p (sudo)"
      sudo apt-get install -y "$p" 2>/dev/null || true
    done
  fi
}

run_rust() {
  command -v rustc &>/dev/null && { skip "Rust"; return 0; }
  log "Installing Rust"; curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y -q 2>/dev/null || true
  [ -f "${HOME}/.cargo/env" ] && . "${HOME}/.cargo/env" 2>/dev/null; export PATH="${HOME}/.cargo/bin:${PATH}"
}

run_node() {
  if command -v fnm &>/dev/null && command -v node &>/dev/null; then skip "Node"; return 0; fi
  command -v fnm &>/dev/null || { log "Installing fnm"; curl -fsSL https://fnm.vercel.app/install | bash 2>/dev/null || true; export PATH="${HOME}/.local/share/fnm:${PATH}"; eval "$(fnm env 2>/dev/null)" || true; }
  command -v fnm &>/dev/null || return 0
  local v=$(json_get "node_version"); v=${v#v}
  [ -n "$v" ] && { fnm install "$v" 2>/dev/null || fnm install --lts 2>/dev/null || true; fnm use "$v" 2>/dev/null || fnm default "$v" 2>/dev/null || true; } || fnm install --lts 2>/dev/null || true
  eval "$(fnm env 2>/dev/null)" || true
  while read -r pkg; do [ -z "$pkg" ] && continue; command -v npm &>/dev/null || continue; npm list -g "$pkg" &>/dev/null && continue; log "npm global $pkg"; npm install -g "$pkg" 2>/dev/null || true; done < <(json_array "npm_global_packages")
}

run_docker() { command -v docker &>/dev/null && { skip "Docker"; return 0; }; log "Installing Docker"; command -v apt-get &>/dev/null && { sudo apt-get update -qq 2>/dev/null; sudo apt-get install -y docker.io 2>/dev/null || true; } || curl -fsSL https://get.docker.com | sh 2>/dev/null || true; }
run_podman() { command -v podman &>/dev/null && { skip "Podman"; return 0; }; log "Installing Podman"; command -v apt-get &>/dev/null && { sudo apt-get update -qq 2>/dev/null; sudo apt-get install -y podman 2>/dev/null || true; }; }
run_kubectl() {
  command -v kubectl &>/dev/null && { skip "kubectl"; return 0; }; log "Installing kubectl"
  local t=$(mktemp); curl -sSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o "$t" 2>/dev/null && chmod +x "$t" && (sudo mv "$t" /usr/local/bin/kubectl 2>/dev/null || mv "$t" "$HOME/.local/bin/kubectl" 2>/dev/null) || rm -f "$t"
}
run_minikube() {
  command -v minikube &>/dev/null && { skip "minikube"; return 0; }; log "Installing minikube"
  command -v apt-get &>/dev/null && sudo apt-get install -y curl conntrack 2>/dev/null || true
  local t=$(mktemp); curl -Lo "$t" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 2>/dev/null && chmod +x "$t" && (sudo mv "$t" /usr/local/bin/minikube 2>/dev/null || mv "$t" "$HOME/.local/bin/minikube" 2>/dev/null) || rm -f "$t"
}
verify_containers() {
  log "Verify containers:"
  for cmd in docker podman kubectl minikube; do
    if command -v "$cmd" &>/dev/null; then
      v=$("$cmd" --version 2>/dev/null || "$cmd" version --client --short 2>/dev/null || "$cmd" version --client 2>/dev/null | head -1)
      log "  $cmd: $v"
    else
      log "  $cmd: not found"
    fi
  done
}
run_containers() { run_docker || true; run_podman || true; run_kubectl || true; run_minikube || true; verify_containers; }

run_vscode_install() {
  command -v code &>/dev/null && { skip "VSCode"; return 0; }
  command -v apt-get &>/dev/null || return 0
  log "Downloading VSCode .deb and installing (sudo)..."
  local deb
  deb=$(mktemp --suffix=.deb)
  wget -qO "$deb" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" 2>/dev/null || { rm -f "$deb"; log "Failed to download VSCode .deb"; return 0; }
  sudo apt-get update -qq 2>/dev/null || true
  sudo dpkg -i "$deb" 2>/dev/null || sudo apt-get -f install -y 2>/dev/null || true
  rm -f "$deb" || true
  if [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
    log "Adding Microsoft VSCode apt repository for automatic updates (sudo)..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null 2>&1 || true
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null 2>&1 || true
    sudo apt-get update -qq 2>/dev/null || true
  else
    log "VSCode apt repository already present (/etc/apt/sources.list.d/vscode.list)."
  fi
}

run_cursor_install() {
  command -v cursor &>/dev/null && { skip "Cursor editor"; return 0; }
  command -v apt-get &>/dev/null || { log "apt-get not found; skip Cursor install"; return 0; }
  log "Downloading Cursor .deb (x64) and installing (sudo)..."
  local deb
  deb=$(mktemp --suffix=.deb)
  # Versioned URL – may need update in future if Cursor changes the path.
  if ! wget -qO "$deb" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.5" 2>/dev/null; then
    rm -f "$deb"
    log "Failed to download Cursor .deb; install manually from https://cursor.com/download."
    return 0
  fi
  sudo apt-get update -qq 2>/dev/null || true
  sudo dpkg -i "$deb" 2>/dev/null || sudo apt-get -f install -y 2>/dev/null || true
  rm -f "$deb" || true
}

run_chrome_install() {
  command -v google-chrome &>/dev/null && { skip "Google Chrome"; return 0; }
  command -v apt-get &>/dev/null || { log "apt-get not found; skip Chrome install"; return 0; }
  log "Downloading Google Chrome .deb (stable) and installing (sudo)..."
  local deb
  deb=$(mktemp --suffix=.deb)
  if ! wget -qO "$deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" 2>/dev/null; then
    rm -f "$deb"
    log "Failed to download Google Chrome .deb; install manually from https://www.google.com/chrome/."
    return 0
  fi
  sudo apt-get update -qq 2>/dev/null || true
  sudo dpkg -i "$deb" 2>/dev/null || sudo apt-get -f install -y 2>/dev/null || true
  rm -f "$deb" || true
}

run_jetbrains_toolbox() {
  local tools_root="$HOME/dev/tools"
  local toolbox_dir="$tools_root/jetbrains-toolbox"
  local toolbox_bin="$toolbox_dir/jetbrains-toolbox"
  if [ -x "$toolbox_bin" ]; then
    skip "JetBrains Toolbox"
    return 0
  fi
  command -v tar &>/dev/null || { log "tar not available; skip JetBrains Toolbox"; return 0; }
  mkdir -p "$tools_root" 2>/dev/null || true
  log "Downloading JetBrains Toolbox tarball..."
  local tarball tmpdir
  tarball=$(mktemp --suffix=.tar.gz)
  # Versioned URL from JetBrains; may need update over time.
  if ! wget -qO "$tarball" "https://download.jetbrains.com/toolbox/jetbrains-toolbox-2.4.0.32175.tar.gz" 2>/dev/null; then
    rm -f "$tarball"
    log "Failed to download JetBrains Toolbox; install manually from https://www.jetbrains.com/toolbox-app/."
    return 0
  fi
  tmpdir=$(mktemp -d)
  tar -xzf "$tarball" -C "$tmpdir" 2>/dev/null || { rm -f "$tarball"; rm -rf "$tmpdir"; log "Failed to extract JetBrains Toolbox tarball."; return 0; }
  rm -f "$tarball"
  # Move extracted folder into tools_root
  local extracted
  extracted=$(find "$tmpdir" -maxdepth 1 -type d -name "jetbrains-toolbox-*" | head -n1)
  if [ -z "$extracted" ]; then
    rm -rf "$tmpdir"
    log "Could not find extracted JetBrains Toolbox directory."
    return 0
  fi
  mv "$extracted" "$toolbox_dir" 2>/dev/null || { rm -rf "$tmpdir"; log "Failed to move JetBrains Toolbox into $toolbox_dir"; return 0; }
  rm -rf "$tmpdir"
  chmod +x "$toolbox_bin" 2>/dev/null || true
  log "JetBrains Toolbox installed under $toolbox_dir"
}

run_vscode_profile() {
  command -v code &>/dev/null || { log "code not in PATH"; return 0; }
  while read -r ext; do [ -z "$ext" ] && continue; code --list-extensions 2>/dev/null | grep -qxF "$ext" && continue; log "VSCode ext $ext"; code --install-extension "$ext" 2>/dev/null || true; done < <(json_array "vscode_extensions")
}

run_cursor_profile() {
  command -v cursor &>/dev/null || { log "cursor not in PATH"; return 0; }
  while read -r ext; do [ -z "$ext" ] && continue; cursor --list-extensions 2>/dev/null | grep -qxF "$ext" && continue; log "Cursor ext $ext"; cursor --install-extension "$ext" 2>/dev/null || true; done < <(json_array "cursor_extensions")
}

run_editors() {
  run_vscode_profile || true
  run_cursor_profile || true
  run_apparmor_editors || true
}

run_config() {
  local dc="${XDG_CONFIG_HOME:-$HOME/.config}"
  [ -f "$CONFIG/git/gitconfig" ] && cp "$CONFIG/git/gitconfig" "$HOME/.gitconfig" 2>/dev/null && log "Restored .gitconfig" || true
  [ -d "$CONFIG/git/config.d" ] && mkdir -p "$dc/git" && cp -r "$CONFIG/git/config.d"/* "$dc/git/" 2>/dev/null && log "Restored git config.d" || true
  [ -f "$CONFIG/ssh/config" ] && mkdir -p "$HOME/.ssh" && cp "$CONFIG/ssh/config" "$HOME/.ssh/config" 2>/dev/null && log "Restored .ssh/config" || true
  [ -f "$CONFIG/os/mimeapps.list" ] && cp "$CONFIG/os/mimeapps.list" "$dc/mimeapps.list" 2>/dev/null && log "Restored mimeapps" || true
  [ -d "$CONFIG/os/autostart" ] && mkdir -p "$dc/autostart" && for f in "$CONFIG/os/autostart"/*.desktop; do [ -f "$f" ] && cp "$f" "$dc/autostart/" 2>/dev/null; done && log "Restored autostart" || true
  [ -f "$CONFIG/mcp/vscode-mcp.json" ] && mkdir -p "$dc/Code/User" && cp "$CONFIG/mcp/vscode-mcp.json" "$dc/Code/User/mcp.json" 2>/dev/null; [ -f "$CONFIG/mcp/cursor-mcp.json" ] && mkdir -p "$HOME/.cursor" && cp "$CONFIG/mcp/cursor-mcp.json" "$HOME/.cursor/mcp.json" 2>/dev/null
  [ -f "$CONFIG/os/dconf-dump.txt" ] && command -v dconf &>/dev/null && log "Desktop: dconf load / < $CONFIG/os/dconf-dump.txt"
  # Start GNOME keyring (Secret Service) for editors if available
  if command -v gnome-keyring-daemon &>/dev/null; then
    if ! dbus-send --session --dest=org.freedesktop.secrets --type=method_call --print-reply /org/freedesktop/secrets org.freedesktop.DBus.Peer.Ping &>/dev/null; then
      log "Starting gnome-keyring-daemon (secrets)..."
      eval "$(gnome-keyring-daemon --start --components=secrets)" 2>/dev/null || true
      [ -n "${SSH_AUTH_SOCK:-}" ] && export SSH_AUTH_SOCK
    else
      skip "Secret Service (gnome-keyring) already running"
    fi
    # Autostart for future sessions
    local as_dir="$dc/autostart"
    local as_file="$as_dir/gnome-keyring-secrets.desktop"
    if [ ! -f "$as_file" ]; then
      mkdir -p "$as_dir" 2>/dev/null || true
      cat >"$as_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=GNOME Keyring (Secrets)
Comment=Start gnome-keyring-daemon for Secret Service API
Exec=/usr/bin/gnome-keyring-daemon --start --components=secrets
X-GNOME-Autostart-enabled=true
EOF
      log "Installed GNOME Keyring (secrets) autostart."
    fi
  fi
  # Swap CapsLock with Ctrl using setxkbmap and add an autostart entry
  if command -v setxkbmap &>/dev/null; then
    if ! setxkbmap -query 2>/dev/null | grep -q 'ctrl:swapcaps'; then
      log "Setting keyboard option ctrl:swapcaps (swap CapsLock with Ctrl)..."
      setxkbmap -option ctrl:swapcaps 2>/dev/null || true
    else
      skip "setxkbmap ctrl:swapcaps already active"
    fi
    local as_dir="$dc/autostart"
    local as_file="$as_dir/setxkb-swapcaps.desktop"
    if [ ! -f "$as_file" ]; then
      mkdir -p "$as_dir" 2>/dev/null || true
      cat >"$as_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=Swap CapsLock and Ctrl
Comment=Swap CapsLock with Ctrl using setxkbmap
Exec=setxkbmap -option ctrl:swapcaps
X-GNOME-Autostart-enabled=true
EOF
      log "Installed setxkbmap autostart (swap CapsLock and Ctrl)."
    fi
  fi
}

run_flatpak() {
  command -v apt-get &>/dev/null || { log "apt-get not found; skip flatpak"; return 0; }
  if ! command -v flatpak &>/dev/null; then
    log "Installing Flatpak (sudo)..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y flatpak 2>/dev/null || true
  else
    skip "Flatpak"
  fi
  if command -v flatpak &>/dev/null; then
    if ! flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
      log "Adding Flathub remote (user scope)..."
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    else
      skip "Flathub remote"
    fi
  fi
}

run_fonts() {
  command -v apt-get &>/dev/null || { log "apt-get not found; skip fonts"; return 0; }
  # Simple fonts that don't require EULA
  local basic_pkgs=(fonts-firacode fonts-hack-ttf fonts-source-code-pro)
  for p in "${basic_pkgs[@]}"; do
    dpkg -l "$p" &>/dev/null && { skip "$p"; continue; }
    log "Installing font package $p (sudo)..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y "$p" 2>/dev/null || log "  install of $p failed; please install manually."
  done
  # Microsoft core fonts (EULA)
  if dpkg -l ttf-mscorefonts-installer &>/dev/null | grep -q '^ii'; then
    skip "ttf-mscorefonts-installer"
  else
    if [ "${RESTORE_ACCEPT_MS_EULA:-false}" = "true" ]; then
      log "Auto-accepting Microsoft core fonts EULA (RESTORE_ACCEPT_MS_EULA=true) and installing ttf-mscorefonts-installer..."
      echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections 2>/dev/null || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ttf-mscorefonts-installer 2>/dev/null || \
        log "  noninteractive install of ttf-mscorefonts-installer failed; you may need to install it manually."
    else
      log "Skipping automatic EULA acceptance for ttf-mscorefonts-installer (RESTORE_ACCEPT_MS_EULA!=true). Install it manually if desired."
    fi
  fi
}

run_claude_code() {
  command -v claude &>/dev/null && { skip "Claude Code"; return 0; }
  log "Installing Claude Code"; curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || true
}

run_apparmor_editors() {
  # Disable AppArmor confinement for VSCode/Cursor if profiles exist
  if ! command -v aa-status &>/dev/null || [ ! -d /etc/apparmor.d ]; then
    skip "AppArmor (aa-status) not available"
    return 0
  fi
  log "Adjusting AppArmor for editors (VSCode/Cursor) if needed..."
  # Known profile names to try; some systems won't have them.
  local profiles=(usr.bin.code cursor)
  for prof in "${profiles[@]}"; do
    local path="/etc/apparmor.d/$prof"
    [ -f "$path" ] || continue
    if aa-status 2>/dev/null | grep -q "$prof"; then
      log "Disabling AppArmor profile $prof (sudo aa-disable)..."
      sudo aa-disable "$prof" 2>/dev/null || true
    else
      skip "AppArmor profile $prof already disabled or not loaded"
    fi
  done
}

verify_cmd() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    local v
    v=$("$cmd" --version 2>/dev/null || "$cmd" version --client --short 2>/dev/null || "$cmd" version --client 2>/dev/null | head -1)
    log "  $cmd: ${v:-installed}"
  else
    log "  $cmd: not found"
  fi
}

verify_summary() {
  log "Verification summary:"
  # Core / prerequisites
  verify_cmd git
  # Language/tooling
  verify_cmd uv
  verify_cmd java
  verify_cmd sdk
  verify_cmd mvn
  verify_cmd gradle
  verify_cmd rustc
  verify_cmd fnm
  verify_cmd node
  verify_cmd npm
  verify_cmd pnpm
  verify_cmd yarn
  # Containers / k8s
  verify_cmd docker
  verify_cmd podman
  verify_cmd kubectl
  verify_cmd minikube
  # Editors
  verify_cmd code
  verify_cmd cursor
  verify_cmd google-chrome
  # JetBrains Toolbox (installed under ~/dev/tools/jetbrains-toolbox)
  if [ -x "$HOME/dev/tools/jetbrains-toolbox/jetbrains-toolbox" ]; then
    log "  jetbrains-toolbox: installed"
  else
    log "  jetbrains-toolbox: not found"
  fi
  # Dev fonts (package presence only)
  for fpkg in fonts-firacode fonts-hack-ttf fonts-source-code-pro ttf-mscorefonts-installer; do
    if dpkg -l "$fpkg" 2>/dev/null | grep -q '^ii'; then
      log "  $fpkg: installed"
    else
      log "  $fpkg: not installed"
    fi
  done
  # Flatpak / Flathub
  if command -v flatpak &>/dev/null; then
    if flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
      log "  flatpak: installed (flathub configured)"
    else
      log "  flatpak: installed (no flathub remote)"
    fi
  else
    log "  flatpak: not found"
  fi
  # Claude Code
  verify_cmd claude
  # NVIDIA tools
  if command -v nvidia-smi &>/dev/null; then
    nsmi=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
    log "  nvidia-smi: ${nsmi:-available}"
  else
    log "  nvidia-smi: not found"
  fi
  # Graphcore hardware
  if lspci 2>/dev/null | grep -qi 'Graphcore'; then
    log "  graphcore: hardware detected (drivers must be installed from Graphcore portal)"
  else
    log "  graphcore: no device detected"
  fi
}

run_group() {
  case "$1" in
    prerequisites) run_prerequisites ;;
    python)        run_python ;;
    java)          run_java ;;
    rust)          run_rust ;;
    node)          run_node ;;
    containers)    run_containers ;;
    vscode_install) run_vscode_install ;;
    cursor_install) run_cursor_install ;;
    chrome_install) run_chrome_install ;;
    jetbrains_toolbox) run_jetbrains_toolbox ;;
    editors)       run_editors ;;
    config)        run_config ;;
    fonts)         run_fonts ;;
    flatpak)       run_flatpak ;;
    claude_code)   run_claude_code ;;
    *) log "Unknown group $1"; return 1 ;;
  esac
}

run_dev_group() {
  case "$1" in
    general)     run_group prerequisites; run_group config; run_group flatpak; run_group claude_code ;;
    dev)         run_group vscode_install; run_group cursor_install; run_group chrome_install; run_group editors; run_group containers ;;
    java)        run_group java ;;
    cpp)         run_group editors ;;
    rust)        run_group rust; run_group editors ;;
    js)          run_group node; run_group editors ;;
    python)      run_group python; run_group editors ;;
    kubernetes)  run_group containers ;;
    fonts)       run_group fonts ;;
    jetbrains)   run_group jetbrains_toolbox ;;
    cursor)      run_group cursor_install; run_group editors ;;
    *)           log "Unknown dev group $1"; return 1 ;;
  esac
}

LIST=; ALL=; GRPS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list-groups) LIST=1; shift ;;
    --all)         ALL=1; shift ;;
    --group)       [ -n "${2:-}" ] && GRPS+=("$2"); shift 2 ;;
    -h|--help)     echo "Usage: $0 [--list-groups|--all|--group NAME ...]. No args: checklist (Space=toggle, Enter=run)."; exit 0 ;;
    *) shift ;;
  esac
done

if [ -n "$LIST" ]; then
  echo "Internal groups: ${RESTORE_GROUPS[*]}"
  echo "Dev menu groups: ${DEV_GROUPS[*]}"
  exit 0
fi

if [ ${#GRPS[@]} -gt 0 ]; then
  for g in "${GRPS[@]}"; do
    log "=== $g ==="
    if printf '%s\n' "${DEV_GROUPS[@]}" | grep -qxF "$g"; then
      run_dev_group "$g" || true
    else
      run_group "$g" || true
    fi
  done
elif [ -n "$ALL" ]; then
  for g in "${RESTORE_GROUPS[@]}"; do log "=== $g ==="; run_group "$g" || true; done
else
  # Simple numeric dev menu (multi-select)
  printf '\033[H\033[J'
  echo "Select dev groups to run (space-separated numbers, Enter to run, q to quit):"
  echo ""
  local idx=1
  for name in "${DEV_GROUPS[@]}"; do
    echo "  $idx) $name"
    idx=$((idx+1))
  done
  echo ""
  printf "Enter numbers (e.g. 1 2 5), 0 or all for everything, or q: "
  read -r line
  [ -z "$line" ] && exit 0
  if printf '%s\n' "$line" | grep -qiE '(^|[[:space:]])q([[:space:]]|$)'; then
    exit 0
  fi
  # Parse selections
  declare -A seen
  # Special: select all dev groups if user typed 'all' or '0'
  if printf '%s\n' "$line" | grep -qiE '(^|[[:space:]])all([[:space:]]|$)'; then
    for ((i=1; i<=${#DEV_GROUPS[@]}; i++)); do
      seen["$i"]=1
    done
  elif printf '%s\n' "$line" | grep -qiE '(^|[[:space:]])0([[:space:]]|$)'; then
    for ((i=1; i<=${#DEV_GROUPS[@]}; i++)); do
      seen["$i"]=1
    done
  else
    for token in $line; do
      case "$token" in
        '' ) continue ;;
        *[!0-9]* ) continue ;;
        * )
          n=$token
          [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#DEV_GROUPS[@]}" ] 2>/dev/null || continue
          seen["$n"]=1
          ;;
      esac
    done
  fi
  for ((i=1; i<=${#DEV_GROUPS[@]}; i++)); do
    if [ "${seen[$i]+set}" ]; then
      name="${DEV_GROUPS[$((i-1))]}"
      log "=== dev group: $name ==="
      run_dev_group "$name" || true
    fi
  done
fi

verify_summary

log "Done. PATH: export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"; . \$HOME/.cargo/env 2>/dev/null; eval \"\$(fnm env 2>/dev/null)\"; . \$HOME/.sdkman/bin/sdkman-init.sh 2>/dev/null"
