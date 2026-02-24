## Regenerate this project (prompt for an AI assistant)

Use this prompt to recreate the repo structure and behavior of my dev-environment restore project on a fresh machine:

---

You are an AI coding assistant. Recreate a small Git repo that contains:

1. A **single entrypoint script** at repo root:
   - File: `restore-environment.sh`
   - Shebang: `#!/usr/bin/env bash`
   - Assumes **Ubuntu Server LTS** (apt-based) and runs under **bash**.
   - Behavior:
     - Treats its own directory as `ROOT`.
     - Expects a `config/` folder next to it, with:
       - `config/installed-tools.json` (tool versions + lists).
       - `config/profiles/vscode/` and `config/profiles/cursor/` (settings/keybindings/snippets).
       - `config/shell/` (dotfiles + bash history seed).
       - `config/git/`, `config/ssh/`, `config/os/`, `config/mcp/`.
     - Exports `PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"` at startup.
     - Creates `results/` at repo root and logs **all stdout+stderr** to a timestamped file:
       - e.g. `results/restore-YYYYMMDD-HHMMSS.log`
       - Uses `exec > >(tee -a "$LOG_FILE") 2>&1` so output is visible and logged.
   - Provides a **group-based restore UI**:
     - Internal groups: `prerequisites`, `python`, `java`, `rust`, `node`, `containers`, `vscode_install`, `cursor_install`, `chrome_install`, `jetbrains_toolbox`, `editors`, `shell`, `fonts`, `flatpak`, `ml`, `pytorch`, `claude_code`.
     - Dev menu groups (high-level; used in interactive menu and with `--group`): `general`, `dev`, `java`, `cpp`, `rust`, `js`, `python`, `kubernetes`, `ml`, `fonts`, `jetbrains`, `cursor`.
     - CLI:
       - No args: interactive **numeric dev menu**:
         - Renders a numbered list of dev groups (general, dev, java, cpp, rust, js, python, kubernetes, ml, fonts, jetbrains, cursor).
         - User types space-separated numbers (e.g. `1 2 5`), or `0` or `all` to select everything, then **Enter** to run.
         - **q** exits without running.
       - `--group NAME` (repeatable): accepts **dev group names** (e.g. jetbrains, cursor, general) or **internal group names** (e.g. jetbrains_toolbox, cursor_install, prerequisites). If NAME is a dev group, runs the corresponding dev group; otherwise runs the internal group.
       - `--all` runs all internal groups non-interactively.
       - `--list-groups` prints the group names.
       - `-h/--help` prints a short usage line.

2. **Group implementations** (idempotent; safe to re-run):
   - `prerequisites`:
     - If `apt-get` unavailable: skip.
     - Installs, when missing:
       - `unzip`, `curl`, `ca-certificates`.
       - `qemu-guest-agent` (and `systemctl enable --now qemu-guest-agent` when available).
       - `build-essential`, `git`, `cinnamon-core` (hard-coded minimal dev/desktop stack; no apt config files).
   - `python`:
     - Installs **uv** from `https://astral.sh/uv/install.sh` if not already on PATH.
   - `java`:
     - Installs **SDKMAN** if needed.
     - Reads `java_version` from `config/installed-tools.json` and normalizes to something like `21.0.8-tem`, defaulting to that when unclear.
     - Installs that JDK via `sdk install java`.
     - Additionally ensures `maven` and `gradle` apt packages are installed when using apt.
   - `rust`:
     - Uses **rustup** (`https://sh.rustup.rs`) when `rustc` is missing.
   - `node`:
     - Uses **fnm** for Node.
     - Installs the Node version from `node_version` in `installed-tools.json` or falls back to LTS.
     - Ensures npm globals in `npm_global_packages` (corepack, npm, pnpm, yarn, etc.) are installed.
   - `containers`:
     - Installs **Docker** (apt `docker.io` or `get.docker.com`), **Podman**, **kubectl** (download from `dl.k8s.io` to `/usr/local/bin` or `~/.local/bin`), and **minikube** (download from `storage.googleapis.com`).
   - `vscode_install`:
     - Downloads the latest VSCode `.deb` from `https://update.code.visualstudio.com/latest/linux-deb-x64/stable`.
     - Installs it via `sudo dpkg -i` + `sudo apt-get -f install -y`.
     - Adds the Microsoft VSCode apt repo `/etc/apt/sources.list.d/vscode.list` and key if missing.
   - `cursor_install`:
     - Downloads the Cursor editor `.deb` for Linux x64 from the Cursor update service (current stable URL).
     - Installs it via `sudo dpkg -i` + `sudo apt-get -f install -y`.
   - `chrome_install`:
     - Downloads the Google Chrome stable `.deb` from `https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`.
     - Installs it via `sudo dpkg -i` + `sudo apt-get -f install -y`.
   - `jetbrains_toolbox`:
     - Downloads the JetBrains Toolbox tarball (current stable URL).
     - Extracts it under `~/dev/tools/jetbrains-toolbox` and marks the toolbox binary as executable.
   - `editors`:
     - For VSCode:
       - Installs extensions listed in `vscode_extensions` from `installed-tools.json` if not already present.
       - Copies settings/keybindings/snippets/profiles from `config/profiles/vscode/` into `~/.config/Code/User`.
     - For Cursor:
       - Same pattern using `cursor` CLI and `config/profiles/cursor/` into `~/.config/Cursor/User`.
     - After profiles are applied, runs an AppArmor helper that disables VSCode/Cursor profiles if present (so they are not confined by AppArmor).
   - `shell`:
     - **Backs up existing `~/.bashrc`** once to `~/.bashrc.restore-default` (if not already backed up).
     - Copies shell dotfiles from `config/shell/` (`.bashrc`, `.profile`, `.bash_logout`, `.inputrc`, `fish/`).
     - Appends the last N lines from `config/shell/bash_history` into `~/.bash_history` **only once**, tracking with a marker file.
     - Restores Git config, SSH config, `mimeapps.list`, `autostart/`, and MCP config.
   - `fonts`:
     - Installs common dev fonts via apt, when missing:
       - `fonts-firacode` (Fira Code)
       - `fonts-hack-ttf` (Hack)
       - `fonts-source-code-pro` (Source Code Pro)
       - `ttf-mscorefonts-installer` (Microsoft core fonts; may need manual EULA acceptance).
   - `flatpak`:
     - Installs `flatpak` via apt if missing.
     - Adds the **Flathub** remote when absent.
   - `pytorch`:
     - If `torch` is already installed (via `uv pip show` or `python3 -c "import torch"`), skips.
     - Otherwise uses `uv pip install --system` to install `torch`, `torchvision`, `torchaudio` from the CUDA index URL (default `cu124`, fallback `cu118`).
   - `ml`:
     - Focused on ML hardware setup (NVIDIA + Graphcore):
       - Blacklists `nouveau` via `/etc/modprobe.d/blacklist-nouveau.conf` and `update-initramfs -u` (requires reboot to fully apply).
       - Installs `nvidia-driver-470-server` (server driver appropriate for Tesla K80) via apt when missing.
       - Detects Graphcore Colossus hardware via `lspci` and logs instructions to install the GC-02-C2 Colossus drivers and SDK manually from the official Graphcore downloads portal (`https://downloads.graphcore.ai`), since no apt repo is available.
   - `claude_code`:
     - Installs the Claude Code CLI via `curl -fsSL https://claude.ai/install.sh | bash` if `claude` is not already on PATH.

3. **Verification summary** (always printed at the end):
   - After all selected groups run, the script prints a concise summary like:
     - Core: git
     - Language/tooling: uv, java, sdk, mvn, gradle, rustc, fnm, node, npm, pnpm, yarn
     - Containers: docker, podman, kubectl, minikube
     - Editors: code, cursor, google-chrome; JetBrains Toolbox (installed under ~/dev/tools/jetbrains-toolbox)
     - Fonts: `fonts-firacode`, `fonts-hack-ttf`, `fonts-source-code-pro`, `ttf-mscorefonts-installer` (installed or not)
     - flatpak (+ whether `flathub` is configured)
     - pytorch (installed or not)
     - claude
     - qemu-guest-agent (installed or not)
     - `nvidia-smi` (NVIDIA driver), and whether Graphcore hardware was detected

4. **Config layout**:
   - `config/profiles/vscode/` and `config/profiles/cursor/`:
     - Global settings/keybindings/snippets at the root.
     - Subfolders for group-specific profiles (each contains a README placeholder):
       - `general/`, `dev/`, `java/`, `cpp/`, `rust/`, `js/`, `python/`, `kubernetes/`

5. **Shell backup behavior**:
   - On first run of `shell` group, if `~/.bashrc` exists and `~/.bashrc.restore-default` does not, copy the existing file to that backup path and log it.
   - Future runs don’t re-backup; they simply restore the tracked config from `config/shell/`.

6. **Wrapper scripts (optional, but present)**:
   - A `groups/` directory at repo root with simple helper scripts:
     - `groups/general.sh`, `groups/dev.sh`, `groups/java.sh`, `groups/cpp.sh`, `groups/rust.sh`, `groups/js.sh`, `groups/python.sh`, `groups/kubernetes.sh`, `groups/ml.sh`
   - Each wrapper:
     - Uses `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`.
     - Delegates to `"$ROOT/restore-environment.sh"` with `--group` flags appropriate for that conceptual group (e.g. `java` group calls `--group java`, `kubernetes` calls `--group containers`, etc.).

7. **Idempotency & safety**:
   - Every installer checks for an existing install first (via `command -v`, `dpkg -l`, or equivalent) and logs `Skip: ...` instead of re-installing.
   - Copy-style “restore” steps (VSCode/Cursor settings, shell dotfiles, keyboard layout/autostart entries) are safe to run multiple times and converge on the same state.
   - The script never fails hard on individual install errors; it logs and continues.

Recreate this project with clean, readable bash (no external dependencies beyond standard Ubuntu packages and the network installers above), matching this behavior as closely as possible.

