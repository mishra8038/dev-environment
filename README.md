# Dev environment restore

Single-file scripts to restore a development environment (editors, languages, containers, ML, fonts, shell, etc.). Idempotent and safe to re-run.

## Scripts

| Script | Target | Package manager |
|--------|--------|-----------------|
| `restore-environment.sh` | Ubuntu 24.04 LTS + Cinnamon | apt/dpkg |
| `restore-environment-mxlinux.sh` | MX Linux (Debian-based) | apt/dpkg |
| `restore-environment-endeavour.sh` | Endeavour Linux (Arch-based) | pacman + AUR (yay/paru) |
| `restore-environment-cachyos.sh` | CachyOS (Arch-based) | pacman + AUR (yay/paru) |
| `restore-environment-manjaro.sh` | Manjaro Linux (Arch-based) | pacman + AUR (yay/paru) |
| `restore-environment-ubuntu-ml.sh` | Ubuntu — GPU/ML drivers + PyTorch | apt |
| `restore-environment-mxlinux-ml.sh` | MX Linux — GPU/ML drivers + PyTorch | apt |
| `restore-environment-endeavour-ml.sh` | Endeavour — GPU/ML drivers + PyTorch | pacman + AUR |
| `restore-environment-cachyos-ml.sh` | CachyOS — GPU/ML drivers + PyTorch | pacman + AUR |

**Universal shell scripts** (OS-independent; no package manager):
| `collect-shell-config.sh` | Collect/backup .bashrc, .profile, .bash_logout, .inputrc, .bash_history, fish/ from $HOME to config/shell |
| `restore-shell-config.sh` | Restore shell config from config/shell to $HOME |

**Ubuntu** and **Arch** scripts differ: Ubuntu uses apt, gnome-keyring, setxkbmap, and AppArmor; Arch scripts (Endeavour, CachyOS) use pacman/AUR, no GNOME packages, no keyring setup, no setxkbmap, no AppArmor. Endeavour and CachyOS assume Plasma or another DE (no Cinnamon/GNOME).

## Usage

1. Copy the repo (or at minimum the chosen script and the `config/` folder) to the target machine.

   **Ubuntu:**
   ```bash
   chmod +x restore-environment.sh
   ./restore-environment.sh
   ```

   **Endeavour / Arch-based:**
   ```bash
   chmod +x restore-environment-endeavour.sh
   ./restore-environment-endeavour.sh
   ```

   **CachyOS:**
   ```bash
   chmod +x restore-environment-cachyos.sh
   ./restore-environment-cachyos.sh
   ```

   **MX Linux:**
   ```bash
   chmod +x restore-environment-mxlinux.sh
   ./restore-environment-mxlinux.sh
   ```

   **Manjaro:**
   ```bash
   chmod +x restore-environment-manjaro.sh
   ./restore-environment-manjaro.sh
   ```

   For Cursor, Chrome, and optional MS fonts on Arch, install an AUR helper first (e.g. `yay` or `paru`). Set `RESTORE_NO_AUR=1` to skip AUR.

   **GPU/ML drivers + PyTorch:** Run the appropriate ML script separately after the main restore (and after `--group python` for PyTorch):
   ```bash
   ./restore-environment-ubuntu-ml.sh     # Ubuntu
   ./restore-environment-mxlinux-ml.sh    # MX Linux
   ./restore-environment-endeavour-ml.sh  # Endeavour
   ./restore-environment-cachyos-ml.sh    # CachyOS
   ```

   **Shell config (any OS):** To backup your current shell config into config/shell, run from the repo root:
   ```bash
   ./collect-shell-config.sh
   ```
   To restore shell config only (without running a full restore):
   ```bash
   ./restore-shell-config.sh
   ```

2. **Interactive dev menu (no args)**  
   Shows a list of **dev groups** (high-level stacks). Type one or more numbers (e.g. `1 2 5`) and press Enter to run. Type `0` or `all` for everything, `q` to quit.

3. **Direct group execution**  
   ```bash
   ./restore-environment.sh --group jetbrains
   ./restore-environment.sh --group prerequisites
   ./restore-environment.sh --all
   ```

4. **Logs**  
   Every run logs to `results/restore-*-YYYYMMDD-HHMMSS.log` while also printing to the terminal.

## Dev groups (high level)

| Group | Ubuntu / MX Linux | Endeavour / CachyOS / Manjaro |
|-------|--------|---------------------|
| **general** | Core apt, gnome-keyring, config (git/SSH/desktop), setxkbmap swap. Ubuntu: cinnamon-core; MX Linux: no desktop package (uses existing XFCE) | Core pacman, config (git/SSH/desktop) (no keyring, no setxkbmap) |
| **dev** | VSCode (.deb), Cursor (.deb), Chrome (.deb), extensions, Docker/Podman/kubectl/minikube, AppArmor relax | VSCode (pacman/AUR), Cursor (AUR only), Chrome (AUR or Chromium), extensions, containers |
| **java** | SDKMAN, JDK, maven, gradle | Same |
| **cpp** | build-essential, editor extensions | Same |
| **rust** | rustup | Same |
| **js** | fnm, Node, npm globals | Same |
| **python** | uv | Same |
| **kubernetes** | Docker, Podman, kubectl, minikube | Same |
| **fonts** | apt: firacode, hack, source-code-pro, ttf-mscorefonts | pacman: nerd-fonts group, JetBrains Mono, ttf-ms-fonts (AUR) |
| **jetbrains** | JetBrains Toolbox to `~/dev/tools/jetbrains-toolbox` | Same |
| **cursor** | Cursor .deb + extensions | Cursor via AUR + extensions |

**Editors (VSCode, Cursor):** Scripts only install extensions from `config/installed-tools.json`. Settings, keybindings, and profiles must be imported manually inside each IDE. The `config/profiles/` folder (if present) is for manual export/import only.

## Notes

- Some steps require `sudo` and may prompt for your password.
- ML/GPU changes (blacklist nouveau, nvidia driver) require a reboot to fully apply.
- **groups/** wrappers (`groups/general.sh`, `groups/ml.sh`, etc.) call `restore-environment.sh` (Ubuntu only). Use the main scripts directly for MX Linux, Endeavour, CachyOS, or Manjaro.
- For a complete spec (internal groups, verification summary, config expectations), see `docs/REGEN_PROMPT.md`.
