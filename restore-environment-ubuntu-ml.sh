#!/usr/bin/env bash
# GPU/ML driver setup on Ubuntu (apt).
# Handles nouveau blacklist, NVIDIA driver, Graphcore detection, and PyTorch separately from the main restore script.
# Usage: ./restore-environment-ubuntu-ml.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

RESULTS="$ROOT/results"
mkdir -p "$RESULTS" 2>/dev/null || true
LOG_FILE="$RESULTS/restore-ubuntu-ml-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[restore-ubuntu-ml] %s\n' "$*" >&2; }
skip() { log "Skip: $*"; }

command -v apt-get &>/dev/null || { log "apt-get not found. This script is for Ubuntu (apt-based) systems."; exit 1; }

run_ml() {
  if ! grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    log "Blacklisting nouveau (sudo, requires reboot to fully apply)..."
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null 2>&1 || true
    sudo update-initramfs -u 2>/dev/null || true
  else
    skip "nouveau already blacklisted"
  fi
  if ! dpkg -l nvidia-driver-470-server 2>/dev/null | grep -q '^ii'; then
    log "Installing NVIDIA 470 server driver for Tesla K80 (sudo)..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y nvidia-driver-470-server 2>/dev/null || true
  else
    skip "nvidia-driver-470-server"
  fi
  if lspci 2>/dev/null | grep -qi 'Graphcore'; then
    log "Graphcore hardware detected. Install GC-02-C2 Colossus drivers and SDK manually from https://downloads.graphcore.ai (see vendor docs)."
  else
    log "No Graphcore device detected (skip Graphcore driver instructions)."
  fi
}

run_pytorch() {
  command -v uv &>/dev/null || { log "Install python/uv first (run main restore --group python)"; return 0; }
  if uv pip show torch &>/dev/null || python3 -c "import torch" 2>/dev/null; then skip "PyTorch"; return 0; fi
  log "Installing PyTorch (CUDA)"; local cu="${RESTORE_PYTORCH_CUDA:-cu124}"
  uv pip install --system torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/${cu}" 2>/dev/null || uv pip install --system torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/cu118" 2>/dev/null || true
}

run_ml
run_pytorch

log "Done. NVIDIA / Graphcore / PyTorch ML setup complete (see log above for details)."
