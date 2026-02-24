#!/usr/bin/env bash
# Collect dev tools and editor profiles from this machine into config/.
# Fail-safe: missing commands or copy errors are logged and skipped.
set -o pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/config"
PROFILES="$CONFIG/profiles"
OUT_JSON="$CONFIG/installed-tools.json"
TMP_JSON="${OUT_JSON}.tmp"

log() { printf '%s\n' "$*" >&2; }
run_quiet() { "$@" 2>/dev/null; }

# Start JSON object
echo '{' > "$TMP_JSON"
need_comma=

append_section() {
  local key="$1"
  local value="$2"
  [ -n "$value" ] || return 0
  value="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//g' | paste -sd ' ' - | sed 's/ *$//')"
  [ -z "$need_comma" ] || echo "," >> "$TMP_JSON"
  printf '  "%s": "%s"' "$key" "$value" >> "$TMP_JSON"
  need_comma=1
}

append_array() {
  local key="$1"
  shift
  [ $# -gt 0 ] || return 0
  [ -z "$need_comma" ] || echo "," >> "$TMP_JSON"
  printf '  "%s": [' "$key" >> "$TMP_JSON"
  local first=1
  for item in "$@"; do
    [ "$first" -eq 1 ] || echo -n "," >> "$TMP_JSON"
    printf '"%s"' "$(printf '%s' "$item" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" >> "$TMP_JSON"
    first=0
  done
  echo "]" >> "$TMP_JSON"
  need_comma=1
}

# --- Java (SDKMAN) ---
java_version=
if command -v sdk &>/dev/null; then
  java_version=$(sdk current java 2>/dev/null | awk '{print $NF}' || true)
fi
[ -z "$java_version" ] && command -v java &>/dev/null && java_version=$(run_quiet java -version 2>&1 | head -1)
[ -n "$java_version" ] && append_section "java_version" "$java_version"

# --- Rust ---
rust_version=
if command -v rustup &>/dev/null; then
  rust_version=$(run_quiet rustup show active-toolchain 2>/dev/null) || rust_version=$(run_quiet rustc --version 2>/dev/null)
fi
[ -z "$rust_version" ] && command -v rustc &>/dev/null && rust_version=$(run_quiet rustc --version 2>/dev/null)
append_section "rust_toolchain" "$rust_version"

# --- Python (uv) ---
uv_version=
command -v uv &>/dev/null && uv_version=$(run_quiet uv --version 2>/dev/null)
append_section "uv_version" "$uv_version"

# --- Node / npm ---
node_version=; npm_version=; node_manager=
command -v node &>/dev/null && node_version=$(run_quiet node -v 2>/dev/null)
command -v npm &>/dev/null && npm_version=$(run_quiet npm -v 2>/dev/null)
command -v fnm &>/dev/null && node_manager="fnm"
command -v nvm &>/dev/null && node_manager="nvm"
append_section "node_version" "$node_version"
append_section "npm_version" "$npm_version"
append_section "node_manager" "$node_manager"

npm_globals=()
if command -v npm &>/dev/null; then
  while read -r pkg; do
    [ -n "$pkg" ] && npm_globals+=("$pkg")
  done < <(npm list -g --depth=0 --json 2>/dev/null | run_quiet jq -r '.dependencies | keys[]?' 2>/dev/null || npm list -g --depth=0 2>/dev/null | awk -F'@' 'NR>1 && /^[├└]/ { gsub(/^[├└─ ]+/, ""); print $1 }')
fi
[ ${#npm_globals[@]} -gt 0 ] && append_array "npm_global_packages" "${npm_globals[@]}"

# --- Containers & K8s ---
docker_version=; podman_version=; kubectl_version=
command -v docker &>/dev/null && docker_version=$(run_quiet docker --version 2>/dev/null)
command -v podman &>/dev/null && podman_version=$(run_quiet podman --version 2>/dev/null)
command -v kubectl &>/dev/null && kubectl_version=$(run_quiet kubectl version --client --short 2>/dev/null || run_quiet kubectl version --client 2>/dev/null | head -1)
append_section "docker_version" "$docker_version"
append_section "podman_version" "$podman_version"
append_section "kubectl_version" "$kubectl_version"

k8s_tools=()
for cmd in minikube kind k9s helm kustomize; do
  if command -v "$cmd" &>/dev/null; then
    v=$(run_quiet "$cmd" version --short 2>/dev/null || run_quiet "$cmd" version 2>/dev/null | head -1)
    k8s_tools+=("$cmd: $v")
  fi
done
[ ${#k8s_tools[@]} -gt 0 ] && append_array "k8s_tools" "${k8s_tools[@]}"

# --- VSCode ---
vscode_extensions=()
if command -v code &>/dev/null; then
  while read -r ext; do [ -n "$ext" ] && vscode_extensions+=("$ext"); done < <(code --list-extensions 2>/dev/null)
fi
[ ${#vscode_extensions[@]} -gt 0 ] && append_array "vscode_extensions" "${vscode_extensions[@]}"

# --- Cursor ---
cursor_extensions=()
if command -v cursor &>/dev/null; then
  while read -r ext; do [ -n "$ext" ] && cursor_extensions+=("$ext"); done < <(cursor --list-extensions 2>/dev/null)
fi
# Merge in profile-specific extension IDs from extensions.json
for extjson in ~/.config/Cursor/User/profiles/*/extensions.json; do
  [ -f "$extjson" ] || continue
  while read -r id; do
    [ -z "$id" ] && continue
    if [[ " ${cursor_extensions[*]} " != *" $id "* ]]; then cursor_extensions+=("$id"); fi
  done < <(run_quiet jq -r '.[].identifier.id // .[].identifier?' "$extjson" 2>/dev/null)
done
[ ${#cursor_extensions[@]} -gt 0 ] && append_array "cursor_extensions" "${cursor_extensions[@]}"

echo ''
echo '}' >> "$TMP_JSON"

# Pretty-print if jq available
if command -v jq &>/dev/null; then
  jq . "$TMP_JSON" > "$OUT_JSON" && rm -f "$TMP_JSON"
else
  mv "$TMP_JSON" "$OUT_JSON"
fi
log "Wrote $OUT_JSON"

# --- Copy editor profiles (fail-safe) ---
copy_safe() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst" 2>/dev/null && log "Copied $src -> $dst" || log "Skip (copy failed): $src"
  else
    log "Skip (missing): $src"
  fi
}

# VSCode User
VSCODE_USER="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
if [ -d "$VSCODE_USER" ]; then
  copy_safe "$VSCODE_USER/settings.json" "$PROFILES/vscode/settings.json"
  copy_safe "$VSCODE_USER/keybindings.json" "$PROFILES/vscode/keybindings.json"
  copy_safe "$VSCODE_USER/snippets" "$PROFILES/vscode/snippets"
  [ -f "$VSCODE_USER/profiles.json" ] && copy_safe "$VSCODE_USER/profiles.json" "$PROFILES/vscode/profiles.json"
  for prof in "$VSCODE_USER"/profiles/*/; do
    [ -d "$prof" ] || continue
    name=$(basename "$prof")
    [ -f "$prof/settings.json" ] && copy_safe "$prof/settings.json" "$PROFILES/vscode/profiles/$name/settings.json"
    [ -f "$prof/keybindings.json" ] && copy_safe "$prof/keybindings.json" "$PROFILES/vscode/profiles/$name/keybindings.json"
  done
fi

# Cursor User
CURSOR_USER="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User"
if [ -d "$CURSOR_USER" ]; then
  copy_safe "$CURSOR_USER/settings.json" "$PROFILES/cursor/settings.json"
  copy_safe "$CURSOR_USER/keybindings.json" "$PROFILES/cursor/keybindings.json"
  copy_safe "$CURSOR_USER/snippets" "$PROFILES/cursor/snippets"
  for prof in "$CURSOR_USER"/profiles/*/; do
    [ -d "$prof" ] || continue
    name=$(basename "$prof")
    [ -f "$prof/settings.json" ] && copy_safe "$prof/settings.json" "$PROFILES/cursor/profiles/$name/settings.json"
    [ -f "$prof/keybindings.json" ] && copy_safe "$prof/keybindings.json" "$PROFILES/cursor/profiles/$name/keybindings.json"
    [ -f "$prof/extensions.json" ] && copy_safe "$prof/extensions.json" "$PROFILES/cursor/profiles/$name/extensions.json"
  done
fi

# --- APT top-level packages (Debian/Ubuntu only; editable list) ---
if [ -x "$REPO_ROOT/scripts/collect-apt-packages.sh" ]; then
  "$REPO_ROOT/scripts/collect-apt-packages.sh" || true
fi

# --- OS customizations, shell config, bash history, git, SSH, MCP, dconf ---
if [ -x "$REPO_ROOT/scripts/collect-os-and-shell.sh" ]; then
  "$REPO_ROOT/scripts/collect-os-and-shell.sh" || true
fi

log "Done. Edit config/ (installed-tools.json, apt-packages.txt, shell/, os/, profiles/) as needed; review bash_history for secrets. Then run restore-environment.sh on the target."
