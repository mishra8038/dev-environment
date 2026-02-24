#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# C++ group: currently uses global apt packages and editor profiles.
bash "$ROOT/restore-environment.sh" --group apt_packages --group editors