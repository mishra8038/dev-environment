## Dev environment restore – chat notes (2026-02-24)

This file summarizes the long AI-assisted setup chat used to build and evolve this `restore-environment.sh` script and its config. It is **not** a verbatim transcript, but it captures the key decisions and groups.

### Goals discussed

- Recreate a portable development environment for a new Ubuntu 24.04 LTS + Cinnamon machine, based on an older workstation.
- Single entrypoint script (`restore-environment.sh`) that:
  - Is idempotent and safe to re-run.
  - Can be copied (with `config/`) and run with minimal input.
  - Offers a dev-group selection menu instead of many separate scripts.
- Support for:
  - VSCode and Cursor profiles (settings, keybindings, snippets).
  - JetBrains Toolbox, Docker/Podman/Kubernetes (kubectl, minikube).
  - Rust, Java (SDKMAN, Maven, Gradle), Node (fnm), Python (uv, PyTorch with CUDA).
  - ML hardware: Tesla K80 (NVIDIA driver 470-server) and Graphcore Colossus.
  - Fonts, shell config, keybindings (CapsLock/Ctrl swap), GNOME keyring, AppArmor relax for editors.

### Key script behaviors (from the chat)

- **Core script structure**
  - Uses `ROOT` as the script directory; expects `config/` next to it.
  - Exports `PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"`.
  - Logs all output to `results/restore-YYYYMMDD-HHMMSS.log` via `exec > >(tee -a "$LOG_FILE") 2>&1`.
  - Fails early if `config/installed-tools.json` is missing.

- **Prerequisites**
  - Installs base apt packages if missing:
    - `unzip`, `curl`, `ca-certificates`.
    - `qemu-guest-agent` + `systemctl enable --now`.
    - Dev/system tools: `build-essential`, `git`, `cinnamon-core`, `systemd-sysv`, `util-linux`.
    - Keyring stack: `gnome-keyring`, `seahorse`, `libsecret-1-0`, `libsecret-tools`.

- **Language / runtime groups**
  - `python`: installs `uv` tool.
  - `java`: installs SDKMAN and JDK (pref from `installed-tools.json`, default `21.0.8-tem`), plus `maven` and `gradle`.
  - `rust`: installs Rust via `rustup`.
  - `node`: installs Node via `fnm` (version from `installed-tools.json` or LTS) and npm globals from `npm_global_packages`.

- **Containers / K8s**
  - `containers`: installs Docker (`docker.io` or `get.docker.com`), Podman, `kubectl` (via dl.k8s.io), and `minikube`.

- **Editors and tools**
  - `vscode_install`: downloads latest VSCode `.deb` and sets up its apt repo.
  - `cursor_install`: downloads Cursor Linux x64 `.deb` from the Cursor update service and installs it.
  - `chrome_install`: downloads Google Chrome stable `.deb` and installs it.
  - `jetbrains_toolbox`: downloads the JetBrains Toolbox tarball and extracts it to `~/dev/tools/jetbrains-toolbox`.
  - `editors`: applies VSCode and Cursor profiles from `config/profiles/` and then:
    - Runs an AppArmor helper that disables VSCode/Cursor profiles if present (so they are not confined).

- **Shell and desktop**
  - `shell`: backs up `~/.bashrc` to `~/.bashrc.restore-default` on first run, then copies shell/git/SSH/desktop/MCP config from `config/`.
  - Appends a trimmed `bash_history` once, tracked with a marker file.
  - Sets keyboard layout `ctrl:swapcaps` via `setxkbmap` and installs autostart `.desktop` for it.
  - Starts GNOME keyring (`gnome-keyring-daemon --start --components=secrets`) when needed and installs an autostart entry for it.

- **Fonts**
  - `fonts`: installs:
    - `fonts-firacode`, `fonts-hack-ttf`, `fonts-source-code-pro`.
    - `ttf-mscorefonts-installer` when `RESTORE_ACCEPT_MS_EULA=true` (preseeds debconf for the EULA), otherwise logs a skip.

- **ML and PyTorch**
  - `ml`: blacklists `nouveau`, installs `nvidia-driver-470-server` for Tesla K80, and logs Graphcore driver instructions when hardware is detected.
  - `pytorch`: installs CUDA-enabled PyTorch (`torch`, `torchvision`, `torchaudio`) via `uv pip` (default `cu124`, fallback `cu118`), skipping if already present.

- **Dev menu**
  - When no args, shows a numbered list of dev groups (general, dev, java, cpp, rust, js, python, kubernetes, ml, fonts, jetbrains, cursor).
  - You can enter numbers like `1 2 9`, or `0`/`all` to select all dev groups, or `q` to quit.
  - Each dev group maps to one or more internal groups.
  - `--group NAME` accepts **dev group names** (e.g. jetbrains, cursor) or **internal group names** (e.g. jetbrains_toolbox, cursor_install); dev names are dispatched via `run_dev_group`, internal names via `run_group`.

- **Verification summary**
  - At the end of every run the script prints a verification summary: git, uv, java, sdk, mvn, gradle, rustc, fnm, node, npm, pnpm, yarn; docker, podman, kubectl, minikube; code, cursor, google-chrome, jetbrains-toolbox; fonts packages; flatpak; pytorch; claude; qemu-guest-agent; nvidia-smi; Graphcore hardware detection.

### Why this file exists

The full chat used to build this script is long and lives outside the repo (in the AI/chat system). This markdown file is a compact historical note so future me (or another assistant) can understand the intent and major design decisions without needing the external transcript.
