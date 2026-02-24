# Restore: What Worked, What Didn’t, What Changed

## Execution findings

**Worked**
- **uv** — Install to `~/.local/bin` succeeded. Needs `~/.local/bin` on PATH.
- **Rust (rustup)** — Installed; needs `source ~/.cargo/env` or new shell.
- **Cursor** — Extensions and profile applied when `cursor` was on PATH.
- **Idempotency** — Skip-if-present kept script re-runnable.

**Failed or skipped**
- **SDKMAN / fnm** — Both require **unzip**. Install failed with “Please install unzip”.
- **Docker / Podman / kubectl** — `sudo` steps failed when run non-interactively (no password).
- **VSCode** — `code` not in PATH; extensions/profile step skipped. Script does not install the binary.
- **APT** — `apt-packages.txt` was empty; no system packages installed.
- **PATH** — Same-session runs didn’t see `~/.local/bin` or `~/.cargo/bin` until script was updated to export PATH at start.

## Changes made
1. **Prerequisites first** — Script installs **unzip**, **curl**, **ca-certificates** before SDKMAN/fnm so their installers can run.
2. **PATH in script** — Script exports `PATH=~/.local/bin:~/.cargo/bin:$PATH` at start so later steps see uv/rust in the same run.
3. **Toolchain groups** — Steps grouped (prerequisites, apt_packages, python, java, rust, node, containers, vscode_install, editors, shell, pytorch, claude_code). Run by name or via UI.
4. **Textual UI** — Interactive run shows a checklist: **[ ]** / **[x]** per group; **Space** toggles, **Enter** runs selected groups. No y/n prompts.
5. **Minimal APT list** — `config/apt-packages.txt` reduced to top-level **cinnamon-core** plus only packages that must be explicitly installed: **unzip**, **curl**, **ca-certificates**, **build-essential**, **git**. No long “noise” list.
6. **Single script** — All restore logic lives in one file: `scripts/restore-environment.sh`.
7. **Optional groups** — **vscode_install** (install `code` binary), **pytorch** (PyTorch + CUDA), **claude_code** (Claude Code CLI) are opt-in via UI or `--group` / `--all`.
8. **Containers** — **minikube** included in containers group (binary to `/usr/local/bin` or `~/.local/bin`).

## Base system

- **Ubuntu Server LTS + cinnamon-core** is a sufficient base for C++/Rust/Java/Python/npm development with Docker, Kubernetes, and virtualization. Keep **cinnamon-core** as the top-level desktop package; other APT entries are only what must be explicitly installed (unzip, curl, ca-certificates, build-essential, git). Language runtimes come from the script (rustup, fnm, SDKMAN, uv).

## Usage

- `./scripts/restore-environment.sh` — Show checklist; Space toggles, Enter runs.
- `./scripts/restore-environment.sh --list-groups` — Print group names.
- `./scripts/restore-environment.sh --group NAME` — Run one group (repeatable).
- `./scripts/restore-environment.sh --all` — Run all groups (no UI).
