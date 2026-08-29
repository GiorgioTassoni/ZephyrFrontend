# Zephyr Music Client — Linux Installation Guide

Applies to **Zephyr Music Client v1.1.2 Preview** (desktop shell in `apps/zephyr_desktop`).

The installer is [`installSelect.sh`](installSelect.sh) — an interactive script that:

- lets you **choose where to install** (user-local, system-wide, or a custom path),
- **detects a previous install and asks before updating it**, including when the
  same version is already installed,
- installs atomically (temp dir + rename), so a failed install never leaves a
  half-written app behind.

---

## 1. Prerequisites

- **Linux** (x86-64). The bundled build is produced for `linux/x64`.
- **For a prebuilt bundle** (recommended): nothing else needed. The bundle is the
  folder containing `frontend`, `data/`, and `lib/`; ship it next to the
  installer as `bundle/`.
- **To build from source**: Flutter (stable channel) with Linux desktop support
  enabled (`flutter config --enable-linux-desktop`).

---

## 2. Quick start

### Option A — install from a prebuilt bundle (end users)

Place the bundle next to the installer:

```
dist/
├── installSelect.sh
└── bundle/
    ├── frontend
    ├── data/…
    └── VERSION          # optional: "1.1.2" (line 1) + "Preview" (line 2)
```

Then run:

```bash
chmod +x installSelect.sh
./installSelect.sh
```

### Option B — install from a source checkout (developers)

From the repository root:

```bash
./installSelect.sh
```

If no build exists yet and Flutter is available, the script builds the release
bundle automatically (`flutter build linux --release --dart-define=RELEASE_CHANNEL=Preview`)
and installs it.

---

## 3. What the installer asks

On an interactive terminal you get two prompts:

```
Where should Zephyr Music Client be installed?
  1) ~/.local/opt/zephyr      (user-local, no admin rights)
  2) /opt/zephyr (system-wide, sudo will be used)
  3) Custom path
Choose [1/2/3, default 1]:
```

If something is already installed in the chosen directory, it asks before
replacing it:

```
You already have Zephyr Music Client v1.1.0 installed in ~/.local/opt/zephyr.
Update available: v1.1.0 -> v1.1.1. Update now? [Y]
```

If the same version is already installed:

```
You already have this version. Update/reinstall it anyway? [N]
```

Answer `y`/`n` (or press Enter for the default shown in brackets).

> Installing into `/opt/zephyr` needs admin rights — the script offers to run
> with `sudo` and asks for confirmation first.

---

## 4. Where things are installed (user-local layout)

| What | Path |
|---|---|
| App files | `~/.local/opt/zephyr/` (or your chosen dir) |
| Launcher | `~/.local/bin/zephyr` (symlink, on your `PATH`) |
| Menu entry | `~/.local/share/applications/com.giorgiotassoni.zephyr.desktop` |
| Version marker | `~/.local/opt/zephyr/.zephyr-version` (used for update checks) |

For a system-wide install (`/opt/zephyr`), the launcher becomes
`/usr/local/bin/zephyr` and the menu entry goes to
`/usr/share/applications/`.

---

## 5. Command-line options

| Option | Meaning |
|---|---|
| `-d, --dir DIR` | Install into `DIR` instead of asking (default `~/.local/opt/zephyr`). |
| `-b, --bundle DIR` | Use a specific bundle directory (`frontend` + `data/` + `lib/`). |
| `-y, --yes` | Auto-answer *yes* to update/overwrite prompts. |
| `-f, --force` | Like `--yes`, **and** allow reinstalling the same version. |
| `-c, --channel NAME` | Release channel label (default `Preview`). |
| `-u, --uninstall` | Remove the install and its launcher/menu entry. |
| `-h, --help` | Show help. |

Examples:

```bash
# Install to a custom location without prompts the menu:
./installSelect.sh --dir "$HOME/apps/zephyr"

# Force-reinstall the exact same version non-interactively:
./installSelect.sh --yes --force --bundle ./bundle

# Uninstall from a system-wide install:
./installSelect.sh --uninstall --dir /opt/zephyr
```

> Non-interactive note: without a terminal, the script **will not** overwrite
> the same version automatically — it aborts with
> `error: the same version is already installed; pass --force to reinstall`.
> Use `--yes` when you want a fully automated update.

---

## 6. Updating to a new version

1. Close Zephyr (the script refuses to replace a running app).
2. Get the new bundle (or pull the new source).
3. Run `./installSelect.sh` again — it reads the version from the bundle's
   `VERSION` marker (or the repository's `apps/zephyr_desktop/pubspec.yaml`)
   and offers to update.
4. The old install is replaced atomically; your app data lives in
   `~/.local/share` and is **not** touched.

---

## 7. Uninstalling

```bash
./installSelect.sh --uninstall          # removes ~/.local/opt/zephyr
./installSelect.sh --uninstall --dir /opt/zephyr
```

This deletes the app directory, the `zephyr` launcher, and the desktop entry.

---

## 8. Running the app

```bash
zephyr          # if ~/.local/bin is on your PATH
~/.local/bin/zephyr
```

Or launch it from the desktop menu ("Zephyr").

---

## 9. Troubleshooting

| Problem | Fix |
|---|---|
| `error: Zephyr Music Client is running` | Close Zephyr before updating/uninstalling. |
| `error: the same version is already installed` | You're already up to date; add `--force` to reinstall anyway. |
| `error: pick a directory you can write to, or run with sudo` | Choose `1)` (user-local) instead of `/opt`, or answer **yes** when it asks to use `sudo`. |
| `error: could not find a Zephyr bundle` | Provide the bundle explicitly: `--bundle /path/to/bundle`, or build first with `flutter build linux --release`. |
| App not in the menu after install | Run `update-desktop-database ~/.local/share/applications`. |