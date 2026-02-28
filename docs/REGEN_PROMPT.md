## Regenerate this project (prompt for an AI assistant)

Use this prompt to recreate the repo structure and behavior of my dev-environment restore project on a fresh machine:

---

You are an AI coding assistant. Recreate a small Git repo that contains:

### Script layout (multiple entrypoints)

- **`restore-environment.sh`** — Ubuntu 24.04 LTS + Cinnamon (apt/dpkg). Full restore; no shell, ml, or pytorch groups (use separate scripts).
- **`restore-environment-mxlinux.sh`** — MX Linux (apt/dpkg). Same as Ubuntu; no cinnamon-core.
- **`restore-environment-endeavour.sh`** — Endeavour Linux (Arch, pacman + AUR). No GNOME, no keyring, no setxkbmap, no AppArmor.
- **`restore-environment-cachyos.sh`** — CachyOS (Arch, pacman + AUR). Same as Endeavour.
- **`restore-environment-manjaro.sh`** — Manjaro (Arch, pacman + AUR). Same as Endeavour.
- **`restore-environment-ubuntu-ml.sh`** — Ubuntu: NVIDIA driver + nouveau blacklist + Graphcore detection + PyTorch.
- **`restore-environment-mxlinux-ml.sh`** — MX Linux: same as ubuntu-ml.
- **`restore-environment-endeavour-ml.sh`** — Endeavour: NVIDIA driver + nouveau blacklist + Graphcore detection + PyTorch.
- **`restore-environment-cachyos-ml.sh`** — CachyOS: same as endeavour-ml.

All scripts share the same `config/` layout. Arch scripts use `yay` or `paru` for AUR (Cursor, Chrome, ttf-ms-fonts). Set `RESTORE_NO_AUR=1` to skip AUR.

### 1. Ubuntu entrypoint script
   - File: `restore-environment.sh`
   - Shebang: `#!/usr/bin/env bash`
   - Assumes **Ubuntu Server LTS** (apt-based) and runs under **bash**.
   - Behavior:
     - Treats its own directory as `ROOT`.
     - Expects a `config/` folder next to it, with:
       - `config/installed-tools.json` (tool versions + extension lists).
       - `config/profiles/vscode/` and `config/profiles/cursor/` (optional; for manual IDE import only — scripts do not copy profiles).
       - `config/shell/` (dotfiles + bash history seed).
       - `config/git/`, `config/ssh/`, `config/os/`, `config/mcp/`.
     - Exports `PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"` at startup.
     - Creates `results/` at repo root and logs **all stdout+stderr** to a timestamped file:
       - e.g. `results/restore-YYYYMMDD-HHMMSS.log`
       - Uses `exec > >(tee -a "$LOG_FILE") 2>&1` so output is visible and logged.
   - Provides a **group-based restore UI**:
     - Internal groups: `prerequisites`, `python`, `java`, `rust`, `node`, `containers`, `vscode_install`, `cursor_install`, `chrome_install`, `jetbrains_toolbox`, `editors`, `config`, `fonts`, `flatpak`, `claude_code`.
     - Dev menu groups (high-level; used in interactive menu and with `--group`): `general`, `dev`, `java`, `cpp`, `rust`, `js`, `python`, `kubernetes`, `fonts`, `jetbrains`, `cursor`.
     - CLI:
       - No args: interactive **numeric dev menu**:
         - Renders a numbered list of dev groups (general, dev, java, cpp, rust, js, python, kubernetes, fonts, jetbrains, cursor).
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
     - For VSCode: Installs extensions listed in `vscode_extensions` from `installed-tools.json` if not already present. Does **not** copy settings/keybindings/profiles — those must be imported manually inside the IDE.
     - For Cursor: Same pattern (extensions only). No profile copy.
     - On Ubuntu only: runs an AppArmor helper that disables VSCode/Cursor profiles if present (so they are not confined by AppArmor).
   - `config`:
     - Restores Git config, SSH config, `mimeapps.list`, `autostart/`, and MCP config.
     - Does **not** restore shell dotfiles (use `restore-shell-config.sh` separately).
   - `fonts`:
     - Installs common dev fonts via apt, when missing:
       - `fonts-firacode` (Fira Code)
       - `fonts-hack-ttf` (Hack)
       - `fonts-source-code-pro` (Source Code Pro)
       - `ttf-mscorefonts-installer` (Microsoft core fonts; may need manual EULA acceptance).
   - `flatpak`:
     - Installs `flatpak` via apt if missing.
     - Adds the **Flathub** remote when absent.
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
     - claude
     - `nvidia-smi` (NVIDIA driver), and whether Graphcore hardware was detected

4. **Config layout**:
   - `config/profiles/vscode/` and `config/profiles/cursor/` (optional):
     - Used for **manual** export/import of settings, keybindings, and profiles inside each IDE. Scripts do not copy these; they only install extensions.

5. **Universal shell scripts** (OS-independent; no apt/pacman):
   - `collect-shell-config.sh`: Copies .bashrc, .profile, .bash_logout, .inputrc, .bash_history, and fish/ from $HOME to config/shell (or DEST argument). Run to capture current shell config before restore.
   - `restore-shell-config.sh`: Restores from config/shell (or SOURCE argument) to $HOME. Backs up existing ~/.bashrc to ~/.bashrc.restore-default once before overwriting. Appends bash_history only once (tracks with .restore_bash_history_done).

6. **Wrapper scripts (optional, Ubuntu only)**:
   - A `groups/` directory at repo root with helper scripts that call `restore-environment.sh` (Ubuntu):
     - `groups/general.sh`, `groups/dev.sh`, `groups/java.sh`, `groups/cpp.sh`, `groups/rust.sh`, `groups/js.sh`, `groups/python.sh`, `groups/kubernetes.sh`, `groups/ml.sh`
   - `groups/ml.sh` calls `restore-environment-ubuntu-ml.sh` (Ubuntu); for Arch, run `restore-environment-endeavour-ml.sh` or `restore-environment-cachyos-ml.sh` directly.
   - Each wrapper uses `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` and delegates to `"$ROOT/restore-environment.sh"` with appropriate `--group` flags. These wrappers work with Ubuntu only; for Endeavour/CachyOS/Manjaro, run the main scripts directly.

7. **Idempotency & safety**:
   - Every installer checks for an existing install first (via `command -v`, `dpkg -l`, `pacman -Qq`, or equivalent) and logs `Skip: ...` instead of re-installing.
   - Copy-style “restore” steps (shell dotfiles, git/SSH config, keyboard layout/autostart on Ubuntu) are safe to run multiple times and converge on the same state.
   - The script never fails hard on individual install errors; it logs and continues.

8. **Arch script specifics** (Endeavour, CachyOS):
   - Use pacman for official packages; yay or paru for AUR.
   - No gnome-keyring, libsecret, seahorse, setxkbmap, or AppArmor.
   - Cursor: AUR only (`cursor-bin`); no .deb fallback.
   - Chrome: AUR `google-chrome` preferred; fallback to `chromium` via pacman.
   - Fonts: `nerd-fonts` group, `ttf-jetbrains-mono`, optional `ttf-ms-fonts` (AUR).
   - ML: Separate `*-ml.sh` scripts (ubuntu-ml, mxlinux-ml, endeavour-ml, cachyos-ml) handle nouveau blacklist, nvidia (or nvidia-470xx-dkms from AUR for Arch), Graphcore detection, and PyTorch. Main restore scripts do not include shell, ml, or pytorch groups.

Recreate this project with clean, readable bash (no external dependencies beyond standard system packages and the network installers above), matching this behavior as closely as possible.

