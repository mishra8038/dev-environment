#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/restore-environment.sh" --group prerequisites --group apt_packages --group shell --group flatpak --group claude_code