<div align="center">

# Swarlex Manager

**One control center for your Windows client mods - Vencord, Spicetify and Millennium - in a single double-click script.**

[![Latest release](https://img.shields.io/github/v/release/swarlex/swarlex-manager?label=release&color=3fb950)](https://github.com/swarlex/swarlex-manager/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078d6)

</div>

Swarlex Manager is a menu-driven console tool that installs, updates, repairs and backs up the mods you run on
Discord, Spotify and Steam. It is a single `.bat` file with no installer: everything it needs is downloaded
from the official sources the first time it is needed, and it keeps itself up to date from this repository.

```
╭──────────────────────────────────────────────────────────────╮
│                        S W A R L E X                         │
│                        Control Center                        │
╰──────────────────────────────────────────────────────────────╯
  ● Discord   : Running          ● Spotify   : Running
  ● Vencord   : Patched          ● Spicetify : Applied
  ● Steam     : Running          ● Millennium: Active
  ● Privilege : Standard         ● Updates   : Protected
────────────────────────────────────────────────────────────────
  [1]  Discord        Patch Discord with Vencord & Plugins
  [2]  Spotify        Spicetify Mods, Updates & Protection
  [3]  Steam          Millennium Themes, Plugins & Updates

  [4]  App Updater    Scan & Upgrade Installed Apps [Winget]
  [5]  Backup         Full Profile Backup & Restore [.zip]

  [6]  Repair         Scan & Fix Common Problems [1-Click]
  [7]  Settings       Preferences, Admin Mode & Logs
```

## Features

### Discord & Vencord
- **Patch Discord** - builds [Vencord](https://github.com/Vendicated/Vencord) from source and injects it into
  every installed Discord build (Stable, PTB, Canary, Development), or just the one you pick.
- **Update Vencord** - pulls the latest source, rebuilds and re-patches in one step.
- **Plugin Hub** - install userplugins straight from a GitHub link, turn them on and off, delete them.
  If a plugin breaks the build, Swarlex finds it and switches it off for you.
- **QuickCSS**, **cache cleaning** (your login is kept) and a clean **uninject**.

### Spotify & Spicetify
- **Apply** and **update** [Spicetify](https://spicetify.app), including the re-apply Spotify needs after it
  updates itself.
- **Update Guard** - stops Spotify from silently updating and wiping your mods.
- **Cache cleaning** (downloaded songs are kept) and a full **restore** to stock Spotify.

### Steam & Millennium
- **Install / update** [Millennium](https://steambrew.app). Every download is checked against the release's
  SHA-256 and every file must carry the publisher's valid code signature before anything is copied.
- **Add-on manager** - turn plugins on and off, switch themes, delete add-ons (to the Recycle Bin).
- Web **cache cleaning** and a clean **uninstall** that keeps your themes, plugins and settings.

### Everything else
- **App Updater** - lists every app with a pending update through `winget` and upgrades them one by one.
- **Backup & restore** - one `.zip` with your Vencord settings, userplugins, Spicetify and Millennium data.
- **Safety snapshots** - taken automatically before every update; *Backup > Undo Last Update* rolls back,
  including the Vencord source itself.
- **One-click Repair** - finds and fixes what client updates tend to break: a Discord update that removed
  Vencord, a Spotify update that removed Spicetify, a Steam update that removed Millennium's loader, stuck git
  state, leftover temp files and more.
- **Self-update** - checks this repository on start and updates itself from *Settings > Swarlex Update*.
- **Logs & history**, **system info** for troubleshooting, optional **start as administrator**.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in)
- An internet connection for installs and updates
- `winget` (*App Installer* from the Microsoft Store) - used to install Git and Node.js automatically
  when Vencord needs them, and by the App Updater

Nothing else needs to be installed by hand. Administrator rights are **not** required.

## Installation

1. Download **`Swarlex-Manager.bat`** from the [latest release](https://github.com/swarlex/swarlex-manager/releases/latest).
2. Put it in a folder of its own (for example `Documents\Swarlex`) and double-click it.

Windows SmartScreen may warn about a downloaded script: choose *More info > Run anyway*.

### Verifying a download

Every release also ships `Swarlex-Manager.bat.sha256`. To check your copy:

```powershell
Get-FileHash .\Swarlex-Manager.bat -Algorithm SHA256
```

The hash must match the one in the `.sha256` file of the same release. Swarlex performs the same check
itself before installing an update.

## Updating

Swarlex checks for a new version in the background every time it starts. When one is available, the
*Settings* entry on the main menu says so - open *Settings > [8] Swarlex Update* to read what changed and
install it. Swarlex downloads the new version, verifies its SHA-256, swaps itself and reopens. The previous
version is kept as `%APPDATA%\Swarlex Manager\Swarlex-Manager.previous.bat`.

## Command line

Swarlex can also run a single task without the menu - handy for shortcuts and scheduled tasks:

| Argument     | What it does                                         |
|--------------|------------------------------------------------------|
| `patch`      | Build Vencord and patch Discord                      |
| `apply`      | Apply Spicetify to Spotify                           |
| `millennium` | Install or update Millennium                         |
| `repair`     | Run Repair and fix everything it finds               |
| `backup`     | Create a full backup on the Desktop                  |
| `restore`    | Restore the newest backup from the Desktop           |
| `discord`, `spotify`, `steam`, `settings` | Open that menu directly |

```bat
Swarlex-Manager.bat repair
```

## Where things are kept

| Path | Contents |
|------|----------|
| `%APPDATA%\Swarlex Manager\settings.ini` | Your settings |
| `%APPDATA%\Swarlex Manager\history.log` | One line per action (*Settings > Action History*) |
| `%APPDATA%\Swarlex Manager\swarlex.log` | Detailed log for troubleshooting (*Settings > Log File*) |
| `%APPDATA%\Swarlex Manager\snapshots\` | Automatic safety snapshots (last 5 per kind) |
| `Desktop\Swarlex_Backup_*.zip` | Full backups you create |
| `Documents\Vencord` | The Vencord source Swarlex builds from |

## What Swarlex changes on your system

Everything below can be undone from inside Swarlex:

- **Discord** - `resources\app.asar` is replaced by a small loader; the original is kept as `_app.asar`
  (*Discord > Uninject* puts it back).
- **Spotify** - Spicetify modifies Spotify's app files (*Spotify > Restore Spotify*). The Update Guard
  replaces `%LOCALAPPDATA%\Spotify\Update` with a locked file (*Update Guard* again unlocks it).
- **Steam** - Millennium adds `wsock32.dll` and `millennium\bin`, `millennium\lib` to the Steam folder
  (*Steam > Uninstall* removes them and keeps your add-ons).

## Building a release (maintainers)

1. Change `set "SWX_VERSION=x.y.z"` near the top of `Swarlex-Manager.bat`.
2. Add a `## [x.y.z]` section to [`CHANGELOG.md`](CHANGELOG.md).
3. Commit, then tag and push:

   ```bash
   git tag vx.y.z
   git push origin main vx.y.z
   ```

The [release workflow](.github/workflows/release.yml) checks that the tag matches `SWX_VERSION`, publishes
`Swarlex-Manager.bat` with its `.sha256`, and uses the changelog section as the release notes. Every
installed copy then offers the update on its next start.

## Disclaimer

Swarlex Manager is an independent project and is not affiliated with or endorsed by Discord, Spotify,
Valve, Vencord, Spicetify or Millennium. Client modifications may be against those services' terms of
service. Use it at your own risk.

## License

Swarlex Manager is free software, released under the [GNU General Public License v3.0](LICENSE) or (at your
option) any later version.
