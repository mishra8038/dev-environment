#!/usr/bin/env bash
# List APT packages that are "top-level" (explicitly installed), i.e. not
# dependencies of any other manually installed package. Output is editable:
# config/apt-packages.txt (one package per line; lines starting with # are comments).
# Fail-safe: skips if not on Debian/Ubuntu or apt-mark fails.
# Uses forward deps (dpkg -s) so one pass over manual list is fast.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config"
OUT="${CONFIG}/apt-packages.txt"
TMP_MANUAL="${CONFIG}/.apt-manual.$$"
TMP_DEPS="${CONFIG}/.apt-deps.$$"

log() { printf '%s\n' "$*" >&2; }
cleanup() { rm -f "$TMP_MANUAL" "$TMP_DEPS" "${TMP_DEPS}.top"; }
trap cleanup EXIT

if ! command -v apt-mark &>/dev/null; then
  log "apt-mark not found (not Debian/Ubuntu). Skip APT package list."
  exit 0
fi

# All manually installed packages
apt-mark showmanual 2>/dev/null | sort -u > "$TMP_MANUAL" || { log "apt-mark showmanual failed."; exit 0; }
count_manual=$(wc -l < "$TMP_MANUAL")

# Required = union of Depends/Pre-Depends of every manual package (package names only).
# Top-level = manual - required.
> "$TMP_DEPS"
while IFS= read -r pkg; do
  [ -z "$pkg" ] && continue
  # Parse Depends and Pre-Depends: "foo (>= 1), bar | baz" -> foo bar baz
  dpkg -s "$pkg" 2>/dev/null | grep -E '^(Depends|Pre-Depends):' | sed 's/^[^:]*:[[:space:]]*//' \
    | tr ',' '\n' | tr '|' '\n' | sed 's/[[:space:]]*(.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' >> "$TMP_DEPS"
done < "$TMP_MANUAL"
sort -u -o "$TMP_DEPS" "$TMP_DEPS" 2>/dev/null

# Top-level = in manual but not in deps (not required by any other manual package)
comm -23 "$TMP_MANUAL" "$TMP_DEPS" > "${TMP_DEPS}.top"
count_top=$(wc -l < "${TMP_DEPS}.top")

{
  echo "# Top-level APT packages (explicitly installed, not deps of other manual packages)."
  echo "# Edit this file: remove lines you don't want restored, add # to comment out."
  echo "# Generated from $count_manual manual → $count_top top-level."
  echo ""
  cat "${TMP_DEPS}.top"
} > "$OUT"
rm -f "${TMP_DEPS}.top"

log "Wrote $OUT ($count_top packages). Edit as needed, then run restore-environment.sh on target."
