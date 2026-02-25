#!/usr/bin/env bash
# Restore dev environment on Endeavour Linux (Arch-based, pacman).
# SCP this file + config/ to the machine, then run: ./restore-environment-endeavour.sh
# Idempotent: skips tools already installed; safe to re-run.
# Requires: pacman. Optional: yay or paru for AUR (Cursor, Chrome, ttf-ms-fonts).
# Does not install any desktop environment (no Cinnamon, GNOME, etc.); use with XFCE, KDE, or any other desktop.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/config"
PROFILES="$CONFIG/profiles"
JSON="$CONFIG/installed-tools.json"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

# Set to 'true' to auto-accept the Microsoft core fonts EULA (AUR ttf-ms-fonts).
export RESTORE_ACCEPT_MS_EULA=${RESTORE_ACCEPT_MS_EULA:-true}

# AUR helper: script tries yay, then paru. Set to skip AUR entirely: RESTORE_NO_AUR=1
export RESTORE_NO_AUR=${RESTORE_NO_AUR:-}

RESULTS="$ROOT/results"
mkdir -p "$RESULTS" 2>/dev/null || true
LOG_FILE="$RESULTS/restore-endeavour-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[restore-endeavour] %s\n' "$*" >&2; }
skip() { log "Skip: $*"; }
json_get() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k] // empty' "$JSON" 2>/dev/null; else grep -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$JSON" 2>/dev/null | sed -n 's/.*:[[:space:]]*"\([^"]*\)".*/\1/p'; fi; }
json_array() { local k="$1"; if command -v jq &>/dev/null; then jq -r --arg k "$k" '.[$k][]? // empty' "$JSON" 2>/dev/null; else sed -n "/\"$k\"[[:space:]]*:/,/\]/p" "$JSON" | grep -o '"[^"]*"' | tr -d '"'; fi; }

[ -f "$JSON" ] || { log "Missing $JSON. Put config/ next to this script (config/installed-tools.json, etc.)."; exit 1; }

command -v pacman &>/dev/null || { log "pacman not found. This script is for Endeavour/Arch-based systems."; exit 1; }

# Resolve AUR helper (yay or paru)
aur_helper() {
  if [ -n "${RESTORE_NO_AUR:-}" ]; then echo ""; return; fi
  command -v yay &>/dev/null && { echo "yay"; return; }
  command -v paru &>/dev/null && { echo "paru"; return; }
  echo ""
}

AUR_HELPER=$(aur_helper)

RESTORE_GROUPS=(prerequisites python java rust node containers vscode_install cursor_install chrome_install jetbrains_toolbox editors shell fonts flatpak pytorch claude_code)
DEFAULT_SEL=(1 1 1 1 1 1 0 0 0 0 1 0 0 0 0 0)

DEV_GROUPS=(general dev java cpp rust js python kubernetes fonts jetbrains cursor)
DEV_DEFAULT_SEL=(1 1 1 1 1 1 1 1 0 0 0 0)

pacman_install() {
  sudo pacman -S --noconfirm --needed "$@" 2>/dev/null || true
}

aur_install() {
  local pkg="$1"
  if [ -z "$AUR_HELPER" ]; then
    log "AUR helper (yay/paru) not found; skip AUR package: $pkg"
    return 1
  fi
  if pacman -Qq "$pkg" &>/dev/null; then
    skip "$pkg (AUR)"
    return 0
  fi
  log "Installing $pkg via $AUR_HELPER (AUR)..."
  if [ "$AUR_HELPER" = "yay" ]; then
    yay -S --noconfirm --needed "$pkg" 2>/dev/null || true
  else
    paru -S --noconfirm --needed "$pkg" 2>/dev/null || true
  fi
}

run_prerequisites() {
  command -v pacman &>/dev/null || return 0
  # Core build and network
  for p in base-devel git unzip curl; do
    pacman -Qq "$p" &>/dev/null && continue
    log "Installing $p (sudo pacman)"
    pacman_install "$p"
  done
  # CA certs (Arch core)
  if ! pacman -Qq ca-certificates &>/dev/null 2>/dev/null; then
    log "Installing ca-certificates (sudo pacman)"
    pacman_install ca-certificates
  fi
  # QEMU guest agent (for VMs)
  if ! pacman -Qq qemu-guest-agent &>/dev/null 2>/dev/null; then
    log "Installing qemu-guest-agent (sudo pacman)"
    pacman_install qemu-guest-agent
    command -v systemctl &>/dev/null && sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
  fi
  skip "Prerequisites (base-devel, git, unzip, zip, curl, ca-certificates, qemu-guest-agent)"
}

run_python() {
  command -v uv &>/dev/null && { skip "uv"; return 0; }
  log "Installing uv"; curl -LsSf https://astral.sh/uv/install.sh | sh || true
  export PATH="${HOME}/.local/bin:${PATH}"
}

run_java() {
  command -v java &>/dev/null && command -v sdk &>/dev/null && { skip "Java"; return 0; }
  # SDKMAN requires zip, unzip, curl; ensure they are installed (e.g. if --group java was run without prerequisites)
  if command -v pacman &>/dev/null; then
    for p in zip unzip curl; do
      if ! command -v "$p" &>/dev/null; then
        log "Installing $p for SDKMAN (sudo pacman)"
        pacman_install "$p"
      fi
    done
  fi
  command -v sdk &>/dev/null || { log "Installing SDKMAN"; curl -s "https://get.sdkman.io" | bash || true; export SDKMAN_DIR="${HOME}/.sdkman"; [ -f "${HOME}/.sdkman/bin/sdkman-init.sh" ] && . "${HOME}/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true; }
  command -v sdk &>/dev/null || return 0
  local w=$(json_get "java_version"); [[ "$w" == *tem* && "$w" == *21* ]] && w="21.0.8-tem" || w="${w:-21.0.8-tem}"; w=$(echo "$w" | tr -d '[:space:]'); [ -z "$w" ] && w="21.0.8-tem"
  log "Installing Java $w"; sdk install java "$w" 2>/dev/null || sdk install java 21.0.8-tem 2>/dev/null || true
  for p in maven gradle; do
    pacman -Qq "$p" &>/dev/null && continue
    log "Installing $p (sudo pacman)"
    pacman_install "$p"
  done
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

run_docker() { command -v docker &>/dev/null && { skip "Docker"; return 0; }; log "Installing Docker"; pacman_install docker; command -v systemctl &>/dev/null && sudo systemctl enable --now docker 2>/dev/null || true; }
run_podman() { command -v podman &>/dev/null && { skip "Podman"; return 0; }; log "Installing Podman"; pacman_install podman; }
run_kubectl() {
  command -v kubectl &>/dev/null && { skip "kubectl"; return 0; }; log "Installing kubectl"
  pacman_install kubectl 2>/dev/null || {
    local t=$(mktemp); curl -sSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o "$t" 2>/dev/null && chmod +x "$t" && (sudo mv "$t" /usr/local/bin/kubectl 2>/dev/null || mv "$t" "$HOME/.local/bin/kubectl" 2>/dev/null) || rm -f "$t"
  }
}
run_minikube() {
  command -v minikube &>/dev/null && { skip "minikube"; return 0; }; log "Installing minikube"
  pacman_install minikube 2>/dev/null || {
    local t=$(mktemp); curl -Lo "$t" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 2>/dev/null && chmod +x "$t" && (sudo mv "$t" /usr/local/bin/minikube 2>/dev/null || mv "$t" "$HOME/.local/bin/minikube" 2>/dev/null) || rm -f "$t"
  }
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
  log "Installing VSCode (code) via pacman..."
  pacman_install code 2>/dev/null || aur_install code 2>/dev/null || log "Install code manually (pacman or AUR)."
}

run_cursor_install() {
  command -v cursor &>/dev/null && { skip "Cursor editor"; return 0; }
  if [ -z "$AUR_HELPER" ]; then
    log "AUR helper (yay/paru) required for Cursor. Install yay then: yay -S cursor-bin"
    return 0
  fi
  log "Installing Cursor via AUR ($AUR_HELPER)..."
  aur_install cursor-bin 2>/dev/null || true
  if command -v cursor &>/dev/null; then return 0; fi
  log "Cursor install failed. Install manually: $AUR_HELPER -S cursor-bin (or cursor-app-bin)"
}

run_chrome_install() {
  command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null || command -v chromium &>/dev/null && { skip "Chrome/Chromium"; return 0; }
  # Prefer Google Chrome via AUR (yay/paru) when available
  if [ -n "$AUR_HELPER" ]; then
    log "Installing Google Chrome via AUR ($AUR_HELPER)..."
    aur_install google-chrome 2>/dev/null || true
  fi
  if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
    return 0
  fi
  log "Installing Chromium via pacman (fallback)..."
  pacman_install chromium 2>/dev/null || log "Install Chromium manually: pacman -S chromium. For Google Chrome use AUR: yay -S google-chrome."
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
  tarball=$(mktemp --suffix=.tar.gz 2>/dev/null || mktemp -t toolbox.XXXXXX.tar.gz)
  if ! curl -sSL -o "$tarball" "https://download.jetbrains.com/toolbox/jetbrains-toolbox-2.4.0.32175.tar.gz" 2>/dev/null; then
    rm -f "$tarball"
    log "Failed to download JetBrains Toolbox; install manually from https://www.jetbrains.com/toolbox-app/."
    return 0
  fi
  tmpdir=$(mktemp -d)
  tar -xzf "$tarball" -C "$tmpdir" 2>/dev/null || { rm -f "$tarball"; rm -rf "$tmpdir"; log "Failed to extract JetBrains Toolbox tarball."; return 0; }
  rm -f "$tarball"
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
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"; [ -d "$PROFILES/vscode" ] || return 0; mkdir -p "$d"
  [ -f "$PROFILES/vscode/settings.json" ] && cp "$PROFILES/vscode/settings.json" "$d/" 2>/dev/null; [ -f "$PROFILES/vscode/keybindings.json" ] && cp "$PROFILES/vscode/keybindings.json" "$d/" 2>/dev/null
  [ -d "$PROFILES/vscode/snippets" ] && cp -r "$PROFILES/vscode/snippets" "$d/" 2>/dev/null; [ -f "$PROFILES/vscode/profiles.json" ] && cp "$PROFILES/vscode/profiles.json" "$d/" 2>/dev/null
  # Also export VSCode profile bundle to ~/dev/tools/profiles/vscode for manual import on other installs
  local tools_profiles_vscode="$HOME/dev/tools/profiles/vscode"
  mkdir -p "$tools_profiles_vscode" 2>/dev/null || true
  [ -f "$PROFILES/vscode/settings.json" ] && cp "$PROFILES/vscode/settings.json" "$tools_profiles_vscode/settings.json" 2>/dev/null
  [ -f "$PROFILES/vscode/keybindings.json" ] && cp "$PROFILES/vscode/keybindings.json" "$tools_profiles_vscode/keybindings.json" 2>/dev/null
  [ -d "$PROFILES/vscode/snippets" ] && cp -r "$PROFILES/vscode/snippets" "$tools_profiles_vscode/" 2>/dev/null
  [ -f "$PROFILES/vscode/profiles.json" ] && cp "$PROFILES/vscode/profiles.json" "$tools_profiles_vscode/profiles.json" 2>/dev/null
}

run_cursor_profile() {
  command -v cursor &>/dev/null || { log "cursor not in PATH"; return 0; }
  while read -r ext; do [ -z "$ext" ] && continue; cursor --list-extensions 2>/dev/null | grep -qxF "$ext" && continue; log "Cursor ext $ext"; cursor --install-extension "$ext" 2>/dev/null || true; done < <(json_array "cursor_extensions")
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User"; [ -d "$PROFILES/cursor" ] || return 0; mkdir -p "$d"
  [ -f "$PROFILES/cursor/settings.json" ] && cp "$PROFILES/cursor/settings.json" "$d/" 2>/dev/null; [ -f "$PROFILES/cursor/keybindings.json" ] && cp "$PROFILES/cursor/keybindings.json" "$d/" 2>/dev/null
  [ -d "$PROFILES/cursor/snippets" ] && cp -r "$PROFILES/cursor/snippets" "$d/" 2>/dev/null
  # Also export Cursor profile bundle to ~/dev/tools/profiles/cursor for manual import on other installs
  local tools_profiles_cursor="$HOME/dev/tools/profiles/cursor"
  mkdir -p "$tools_profiles_cursor" 2>/dev/null || true
  [ -f "$PROFILES/cursor/settings.json" ] && cp "$PROFILES/cursor/settings.json" "$tools_profiles_cursor/settings.json" 2>/dev/null
  [ -f "$PROFILES/cursor/keybindings.json" ] && cp "$PROFILES/cursor/keybindings.json" "$tools_profiles_cursor/keybindings.json" 2>/dev/null
  [ -d "$PROFILES/cursor/snippets" ] && cp -r "$PROFILES/cursor/snippets" "$tools_profiles_cursor/" 2>/dev/null
}

run_editors() {
  run_vscode_profile || true
  run_cursor_profile || true
}

run_shell() {
  local dc="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.bashrc.restore-default" ]; then
    cp "$HOME/.bashrc" "$HOME/.bashrc.restore-default" 2>/dev/null && log "Backed up .bashrc to .bashrc.restore-default" || true
  fi
  for f in .bashrc .profile .bash_logout .inputrc; do [ -f "$CONFIG/shell/$f" ] && cp "$CONFIG/shell/$f" "$HOME/$f" 2>/dev/null && log "Restored $f" || true; done
  [ -d "$CONFIG/shell/fish" ] && cp -r "$CONFIG/shell/fish" "$dc/" 2>/dev/null && log "Restored fish" || true
  if [ -f "$CONFIG/shell/bash_history" ] && [ ! -f "$HOME/.restore_bash_history_done" ]; then
    grep -v '^#' "$CONFIG/shell/bash_history" 2>/dev/null | grep -v '^$' | tail -n 5000 >> "$HOME/.bash_history" 2>/dev/null && touch "$HOME/.restore_bash_history_done" && log "Appended bash_history" || true
  fi
  [ -f "$CONFIG/git/gitconfig" ] && cp "$CONFIG/git/gitconfig" "$HOME/.gitconfig" 2>/dev/null && log "Restored .gitconfig" || true
  [ -d "$CONFIG/git/config.d" ] && mkdir -p "$dc/git" && cp -r "$CONFIG/git/config.d"/* "$dc/git/" 2>/dev/null && log "Restored git config.d" || true
  [ -f "$CONFIG/ssh/config" ] && mkdir -p "$HOME/.ssh" && cp "$CONFIG/ssh/config" "$HOME/.ssh/config" 2>/dev/null && log "Restored .ssh/config" || true
  [ -f "$CONFIG/os/mimeapps.list" ] && cp "$CONFIG/os/mimeapps.list" "$dc/mimeapps.list" 2>/dev/null && log "Restored mimeapps" || true
  [ -d "$CONFIG/os/autostart" ] && mkdir -p "$dc/autostart" && for f in "$CONFIG/os/autostart"/*.desktop; do [ -f "$f" ] && cp "$f" "$dc/autostart/" 2>/dev/null; done && log "Restored autostart" || true
  [ -f "$CONFIG/mcp/vscode-mcp.json" ] && mkdir -p "$dc/Code/User" && cp "$CONFIG/mcp/vscode-mcp.json" "$dc/Code/User/mcp.json" 2>/dev/null; [ -f "$CONFIG/mcp/cursor-mcp.json" ] && mkdir -p "$HOME/.cursor" && cp "$CONFIG/mcp/cursor-mcp.json" "$HOME/.cursor/mcp.json" 2>/dev/null
  [ -f "$CONFIG/os/dconf-dump.txt" ] && command -v dconf &>/dev/null && log "Desktop: dconf load / < $CONFIG/os/dconf-dump.txt"
}

run_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    log "Installing Flatpak (sudo pacman)..."
    pacman_install flatpak
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
  # Pacman font packages: nerd-fonts group (complete set, official Extra repo) and JetBrains Mono
  # nerd-fonts group includes ttf-jetbrains-mono-nerd, ttf-firacode-nerd, ttf-nerd-fonts-symbols, etc.
  if ! pacman -Qg nerd-fonts &>/dev/null 2>/dev/null; then
    log "Installing nerd-fonts group (complete) via pacman..."
    pacman_install nerd-fonts || log "  install of nerd-fonts group failed; please install manually."
  else
    skip "nerd-fonts group"
  fi
  # JetBrains Mono (base font; nerd-patched variant is in nerd-fonts group)
  if ! pacman -Qq ttf-jetbrains-mono &>/dev/null 2>/dev/null; then
    log "Installing ttf-jetbrains-mono via pacman..."
    pacman_install ttf-jetbrains-mono || log "  install of ttf-jetbrains-mono failed; please install manually."
  else
    skip "ttf-jetbrains-mono"
  fi
  # Microsoft core fonts (AUR, EULA)
  if pacman -Qq ttf-ms-fonts &>/dev/null 2>/dev/null; then
    skip "ttf-ms-fonts"
  else
    if [ "${RESTORE_ACCEPT_MS_EULA:-false}" = "true" ]; then
      log "Installing ttf-ms-fonts from AUR (EULA accepted via RESTORE_ACCEPT_MS_EULA=true)..."
      aur_install ttf-ms-fonts || log "  install of ttf-ms-fonts failed or AUR disabled; install manually if desired."
    else
      log "Skipping ttf-ms-fonts (RESTORE_ACCEPT_MS_EULA!=true). Install from AUR manually if desired."
    fi
  fi
}

run_pytorch() {
  command -v uv &>/dev/null || { log "Install python group first"; return 0; }
  if uv pip show torch &>/dev/null || python3 -c "import torch" 2>/dev/null; then skip "PyTorch"; return 0; fi
  log "Installing PyTorch (CUDA)"; local cu="${RESTORE_PYTORCH_CUDA:-cu124}"
  uv pip install --system torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/${cu}" 2>/dev/null || uv pip install --system torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/cu118" 2>/dev/null || true
}

run_claude_code() {
  command -v claude &>/dev/null && { skip "Claude Code"; return 0; }
  log "Installing Claude Code"; curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || true
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
  verify_cmd git
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
  verify_cmd docker
  verify_cmd podman
  verify_cmd kubectl
  verify_cmd minikube
  verify_cmd code
  verify_cmd cursor
  if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then log "  chrome: installed (Google Chrome)"; elif command -v chromium &>/dev/null; then log "  chrome: installed (Chromium)"; else log "  chrome: not found"; fi
  if [ -x "$HOME/dev/tools/jetbrains-toolbox/jetbrains-toolbox" ]; then
    log "  jetbrains-toolbox: installed"
  else
    log "  jetbrains-toolbox: not found"
  fi
  for fpkg in ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd ttf-jetbrains-mono ttf-ms-fonts; do
    if pacman -Qq "$fpkg" &>/dev/null 2>/dev/null; then
      log "  $fpkg: installed"
    else
      log "  $fpkg: not installed"
    fi
  done
  if command -v flatpak &>/dev/null; then
    if flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
      log "  flatpak: installed (flathub configured)"
    else
      log "  flatpak: installed (no flathub remote)"
    fi
  else
    log "  flatpak: not found"
  fi
  if uv pip show torch &>/dev/null 2>/dev/null || python3 -c "import torch" 2>/dev/null; then
    log "  pytorch: installed"
  else
    log "  pytorch: not installed"
  fi
  verify_cmd claude
  if pacman -Qq qemu-guest-agent &>/dev/null 2>/dev/null || [ -x /usr/sbin/qemu-ga ]; then
    log "  qemu-guest-agent: installed"
  else
    log "  qemu-guest-agent: not found"
  fi
  if command -v nvidia-smi &>/dev/null; then
    nsmi=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
    log "  nvidia-smi: ${nsmi:-available}"
  else
    log "  nvidia-smi: not found"
  fi
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
    shell)         run_shell ;;
    fonts)         run_fonts ;;
    flatpak)       run_flatpak ;;
    pytorch)       run_pytorch ;;
    claude_code)   run_claude_code ;;
    *) log "Unknown group $1"; return 1 ;;
  esac
}

run_dev_group() {
  case "$1" in
    general)     run_group prerequisites; run_group shell; run_group flatpak; run_group claude_code ;;
    dev)         run_group vscode_install; run_group cursor_install; run_group chrome_install; run_group editors; run_group containers ;;
    java)        run_group java ;;
    cpp)         run_group editors ;;
    rust)        run_group rust; run_group editors ;;
    js)          run_group node; run_group editors ;;
    python)      run_group python; run_group pytorch; run_group editors ;;
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
    -h|--help)     echo "Usage: $0 [--list-groups|--all|--group NAME ...]. No args: checklist (Space=toggle, Enter=run). For Endeavour/Arch (pacman)."; exit 0 ;;
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
  printf '\033[H\033[J'
  echo "Select dev groups to run (space-separated numbers, Enter to run, q to quit):"
  echo ""
  idx=1
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
  declare -A seen
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
