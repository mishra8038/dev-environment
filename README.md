# Development Environment Replication

Scripts and configuration to **capture** your current dev setup and **restore** it on another machine. All install steps are **fail-safe**: if something is already installed or an install fails, the script logs and continues.

## Layout

```
dev-environment/
├── README.md                 # This file
├── config/                   # Generated & stored config (commit or .gitignore)
│   ├── installed-tools.json  # Output of collect-tools.sh
│   ├── apt-packages.txt      # Top-level APT packages (editable)
│   ├── profiles/             # VSCode & Cursor profile snapshots
│   │   ├── vscode/
│   │   └── cursor/
│   ├── shell/               # Shell config & bash history (from collect-os-and-shell.sh)
│   │   ├── .bashrc, .profile, .bash_logout, .inputrc, fish/, bash_history
│   ├── os/                  # OS customizations
│   │   ├── mimeapps.list, autostart/, apt-sources-list.d.txt, dconf-dump.txt
│   ├── git/                 # .gitconfig, config.d
│   ├── ssh/                 # ssh config only (no keys)
│   └── mcp/                 # VSCode/Cursor MCP config (vscode-mcp.json, cursor-mcp.json)
└── scripts/
    ├── collect-tools.sh      # Run on source: tools + profiles + apt + OS/shell
    ├── list-tools.sh         # Show collected tools (needs jq for pretty output)
    ├── collect-apt-packages.sh   # APT top-level only (Debian/Ubuntu)
    ├── collect-os-and-shell.sh   # Shell, history, git, SSH, MCP, dconf, mimeapps, autostart
    └── restore-environment.sh   # Run on target: install & apply all of the above
```

## How to use

### On the machine you want to replicate (source)

1. Clone or copy this repo.
2. Run the collector (no sudo required for listing; profile copy uses your home dir):

   ```bash
   ./scripts/collect-tools.sh
   ```

   This writes:
   - `config/installed-tools.json` — versions and lists (Java, Rust, Python, Node, Docker, K8s, VSCode/Cursor extensions, etc.).
   - `config/apt-packages.txt` — **top-level** APT packages only. Edit to add/remove packages before restore.
   - `config/profiles/vscode/` and `config/profiles/cursor/` — editor settings, keybindings, snippets, extensions.
   - `config/shell/` — `.bashrc`, `.profile`, `.bash_logout`, `.inputrc`, Fish config, **bash_history** (see security note below).
   - `config/os/` — `mimeapps.list`, autostart `.desktop` files, APT sources list, **dconf** dump (desktop/panel/keyboard).
   - `config/git/`, `config/ssh/` (config only, no keys), `config/mcp/` — Git, SSH, and MCP config.

3. Optionally run `./scripts/list-tools.sh` to view a summary of collected tools.
4. Commit `config/` (or copy it to the target by any means).

### On the new machine (target)

1. Clone or copy this repo (including `config/`).
2. Run the restore script (some steps may need sudo for system packages):

   ```bash
   ./scripts/restore-environment.sh
   ```

   It will:
   - Install or skip: **APT packages**, then **uv**, **SDKMAN + Java**, **Rust**, **Node** (fnm + npm), **Docker**, **Podman**, **kubectl**.
   - Install VSCode/Cursor extensions and copy editor profiles.
   - Restore **shell** dotfiles (`.bashrc`, `.profile`, etc.), **append** bash history, **Git** config, **SSH config** (no keys), **mimeapps.list**, **autostart**, **MCP** config. Optionally restore **dconf** (desktop settings) — see log message.

   Any step that fails or is already satisfied is skipped and the script continues.

## Environment isolation (as on source)

- **Python**: `uv` for projects and venvs.
- **Java**: **SDKMAN** for JDK versions.
- **JavaScript/React/Angular**: **npm** (or pnpm/yarn) per project; Node via **fnm** (or nvm) so versions are isolated.

Docker, Podman, and Kubernetes tools are installed system-wide where possible; versions are recorded so you can match them if needed.

## Requirements

- **collect-tools.sh**: bash, `jq` (optional). Editors (code/cursor) optional if not installed.
- **list-tools.sh**: bash, `jq` (optional) to pretty-print the collected tool list.
- **collect-os-and-shell.sh**: bash; optional `dconf` for desktop dump. Copies from `$HOME` and `$XDG_CONFIG_HOME`.
- **restore-environment.sh**: bash, curl, sudo for system packages. Installs SDKMAN, rustup, fnm, uv when missing.

## Security

- **`config/shell/bash_history`** may contain secrets (passwords, tokens, paths). Review before committing or sharing; consider adding `config/shell/bash_history` to `.gitignore` if you sync via git.
- **`config/ssh/config`** contains host names and options only (no private keys are collected). Still review for internal hostnames or sensitive comments.

## Optional

- Add `config/` (or specific files like `config/shell/bash_history`) to `.gitignore` if you prefer not to commit them; then copy to the target manually (rsync, USB, etc.).
- To restore desktop customizations (Cinnamon/GNOME): run `dconf load / < config/os/dconf-dump.txt` after reviewing the file.
