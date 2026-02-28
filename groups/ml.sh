#!/usr/bin/env bash
# Run ML script (GPU drivers + PyTorch). Uses Ubuntu ML script; for Arch use restore-environment-endeavour-ml.sh or restore-environment-cachyos-ml.sh directly.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/restore-environment-ubuntu-ml.sh"

