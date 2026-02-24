# Dev environment restore

SCP `restore-environment.sh` and the `config/` folder to an Ubuntu Server LTS box, then run:

```bash
chmod +x restore-environment.sh
./restore-environment.sh
```

Config must contain at least `config/installed-tools.json`; other files in `config/` (apt-packages.txt, profiles/, shell/, git/, ssh/, os/, mcp/) are used when present. No args: interactive checklist (Space=toggle, Enter=run). `--all` runs every group; `--group NAME` runs one.
