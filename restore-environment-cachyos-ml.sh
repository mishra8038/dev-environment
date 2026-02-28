#!/usr/bin/env bash
# GPU/ML driver setup on CachyOS (Arch-based, pacman).
# Handles NVIDIA driver install, Graphcore detection, and PyTorch separately from the main restore script.
# Usage: ./restore-environment-cachyos-ml.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

# AUR helper: script tries yay, then paru. Set to skip AUR entirely: RESTORE_NO_AUR=1
export RESTORE_NO_AUR=${RESTORE_NO_AUR:-}

RESULTS="$ROOT/results"
mkdir -p "$RESULTS" 2>/dev/null || true
LOG_FILE="$RESULTS/restore-cachyos-ml-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[restore-cachyos-ml] %s\n' "$*" >&2; }
skip() { log "Skip: $*"; }

command -v pacman &>/dev/null || { log "pacman not found. This script is for CachyOS/Arch-based systems."; exit 1; }

aur_helper() {
  if [ -n "${RESTORE_NO_AUR:-}" ]; then echo ""; return; fi
  command -v yay &>/dev/null && { echo "yay"; return; }
  command -v paru &>/dev/null && { echo "paru"; return; }
  echo ""
}

AUR_HELPER=$(aur_helper)

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

run_ml() {
  # Blacklist nouveau to prefer proprietary NVIDIA driver
  if ! grep -q '^blacklist nouveau' /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    log "Blacklisting nouveau (sudo, requires reboot to fully apply)..."
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null 2>&1 || true
    sudo mkinitcpio -P 2>/dev/null || true
  else
    skip "nouveau already blacklisted"
  fi
  # NVIDIA: use main nvidia package; for older GPUs (e.g. Tesla K80) use nvidia-470xx-dkms from AUR
  if ! pacman -Qq nvidia &>/dev/null && ! pacman -Qq nvidia-470xx-dkms &>/dev/null 2>/dev/null; then
    log "Installing NVIDIA driver (nvidia) via pacman..."
    pacman_install nvidia 2>/dev/null || aur_install nvidia-470xx-dkms 2>/dev/null || log "Install nvidia or nvidia-470xx-dkms manually for your GPU."
  else
    skip "nvidia driver"
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

