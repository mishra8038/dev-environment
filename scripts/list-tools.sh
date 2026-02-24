#!/usr/bin/env bash
# Print collected dev tools from config/installed-tools.json (readable summary).
# Run collect-tools.sh first if the file is missing.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON="$REPO_ROOT/config/installed-tools.json"

if [ ! -f "$JSON" ]; then
  echo "No config/installed-tools.json found. Run: ./scripts/collect-tools.sh" >&2
  exit 1
fi

if command -v jq &>/dev/null; then
  jq -r '
    "Java:     " + (.["java_version"] // "—"),
    "Rust:     " + (.["rust_toolchain"] // "—"),
    "uv:       " + (.["uv_version"] // "—"),
    "Node:     " + (.["node_version"] // "—"),
    "npm:      " + (.["npm_version"] // "—"),
    "Docker:   " + (.["docker_version"] // "—"),
    "Podman:   " + (.["podman_version"] // "—"),
    "kubectl:  " + (.["kubectl_version"] // "—"),
    "K8s:      " + (if .["k8s_tools"] then (.["k8s_tools"] | join(", ")) else "—" end),
    "VSCode:   " + (if .["vscode_extensions"] then (.["vscode_extensions"] | length | tostring) + " extensions" else "—" end),
    "Cursor:   " + (if .["cursor_extensions"] then (.["cursor_extensions"] | length | tostring) + " extensions" else "—" end)
  ' "$JSON" 2>/dev/null
  echo ""
  for key in vscode_extensions cursor_extensions npm_global_packages k8s_tools; do
    if jq -e ".[\"$key\"] | length > 0" "$JSON" &>/dev/null; then
      echo "--- $key ---"
      jq -r ".[\"$key\"][]?" "$JSON" 2>/dev/null | sed 's/^/  /'
    fi
  done
else
  echo "Install jq for a readable summary, or open: $JSON"
  cat "$JSON"
fi
