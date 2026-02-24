# Dev environment restore

Single-file script to restore my Ubuntu 24.04 LTS + Cinnamon development environment (editors, languages, containers, ML, fonts, shell, keyring, etc.). It is idempotent and safe to re-run.

## Usage

1. Copy the repo (or at minimum `restore-environment.sh` and the `config/` folder) to the target machine:

   ```bash
   chmod +x restore-environment.sh
   ./restore-environment.sh
   ```

2. **Interactive dev menu (no args)**  
   - Shows a list of **dev groups** (high-level stacks) such as:
     - `general`, `dev`, `java`, `cpp`, `rust`, `js`, `python`, `kubernetes`, `ml`, `fonts`, `jetbrains`, `cursor`
   - Controls:
     - Type one or more **numbers** (e.g. `1 2 5`) and press **Enter** to run those dev groups.
     - Type `0` or `all` to run **all** dev groups.
     - Type `q` to quit the menu without running anything.

3. **Direct group execution (optional)**  
   - Run an internal group directly:

     ```bash
     ./restore-environment.sh --group prerequisites
     ./restore-environment.sh --group containers
     ```

   - Run all internal groups non-interactively:

     ```bash
     ./restore-environment.sh --all
     ```

4. **Logs**  
   - Every run logs to `results/restore-YYYYMMDD-HHMMSS.log` while also printing to the terminal.

## What dev groups do (high level)

- **general**
  - Core apt stack: `unzip`, `curl`, `ca-certificates`, `qemu-guest-agent`, `build-essential`, `git`, `cinnamon-core`, `gnome-keyring`, `seahorse`, `libsecret`.
  - Restores shell/git/SSH/desktop config from `config/`.
  - Backs up existing `~/.bashrc` once to `~/.bashrc.restore-default`.
  - Appends bash history from `config/shell/bash_history` once.
  - Swaps CapsLock and Ctrl using `setxkbmap -option ctrl:swapcaps` and installs an autostart `.desktop` for it.
  - Starts GNOME keyring (Secret Service) for editors and adds a keyring-autostart `.desktop`.

- **dev**
  - Installs VSCode (latest `.deb` from Microsoft + apt repo).
  - Applies VSCode and Cursor profiles (settings/keybindings/snippets) from `config/profiles/`.
  - Installs Docker, Podman, kubectl, and minikube.
  - Relaxes AppArmor profiles for VSCode/Cursor if present (disables their profiles).

- **java**
  - Installs SDKMAN, JDK (from `config/installed-tools.json` or default `21.0.8-tem`).
  - Installs `maven` and `gradle` via apt.

- **cpp**
  - Relies on `build-essential` from `general` and applies editor profiles.

- **rust**
  - Installs Rust via `rustup` (stable toolchain) and applies editor profiles.

- **js**
  - Installs Node via `fnm` (version from `installed-tools.json` or LTS).
  - Installs npm globals (corepack, npm, pnpm, yarn, etc.) from `installed-tools.json`.
  - Applies editor profiles.

- **python**
  - Installs `uv` (Python toolchain).
  - Installs CUDA-enabled PyTorch (`torch`, `torchvision`, `torchaudio`) via `uv pip` if not already present.
  - Applies editor profiles.

- **kubernetes**
  - Runs the containers stack: Docker, Podman, kubectl, minikube.

- **ml**
  - Blacklists `nouveau` and updates initramfs (requires reboot).
  - Installs `nvidia-driver-470-server` for Tesla K80 (if missing).
  - Detects Graphcore Colossus hardware and logs manual driver/SDK install instructions.
  - Also runs the PyTorch group (CUDA PyTorch install) as part of the ML dev group flow.

- **fonts**
  - Installs dev fonts via apt:
    - `fonts-firacode`, `fonts-hack-ttf`, `fonts-source-code-pro`, `ttf-mscorefonts-installer`.

- **jetbrains**
  - Downloads JetBrains Toolbox tarball.
  - Extracts it to `~/dev/tools/jetbrains-toolbox` and makes the toolbox binary executable.

- **cursor**
  - Downloads Cursor `.deb` for Linux x64 from the Cursor update service.
  - Installs it via `dpkg` + `apt-get -f install`.

## Notes

- The script assumes **Ubuntu 24.04 LTS** (apt-based) and a Cinnamon desktop (for `cinnamon-core`, autostart paths, etc.).
- Some steps require `sudo` and may prompt for your password.
- ML group changes graphics drivers; expect to reboot after running `ml`.
- For a complete spec (internal groups, verification summary, config expectations), see `docs/REGEN_PROMPT.md`.\n*** End Patch```} -->
