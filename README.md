<div align="center">

<img src="docs/banner.svg" alt="Swarlex Manager - one control center for Vencord, Spicetify and Millennium" width="100%">

<br>

**Install, update, repair and back up Vencord, Spicetify and Millennium from one double-click script.**

[![Latest release](https://img.shields.io/github/v/release/swarlex/SwarlexManager?label=release&color=3fb950&cacheSeconds=600)](https://github.com/swarlex/SwarlexManager/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/swarlex/SwarlexManager/total?color=61d6d6&cacheSeconds=600)](https://github.com/swarlex/SwarlexManager/releases)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078d6)

### [⬇ Download Swarlex-Manager.bat](https://github.com/swarlex/SwarlexManager/releases/latest/download/Swarlex-Manager.bat)

<sub>Single file · no installer · no admin rights · updates itself</sub>

[Quick start](#quick-start) · [Features](#features) · [Screenshots](#screenshots) · [FAQ](#faq) · [Changelog](CHANGELOG.md)

<br>

<img src="docs/main-menu.svg" alt="Swarlex Manager main menu" width="660">

</div>

Swarlex Manager is a menu-driven console tool that installs, updates, repairs and backs up the mods you run on
Discord, Spotify and Steam. It is a single `.bat` file with no installer: everything it needs is downloaded
from the official sources the first time it is needed, and it keeps itself up to date from this repository.

<p align="center"><img src="docs/features.svg" alt="Patch every Discord, Plugin Hub, Update Guard, Verified Millennium, One-click Repair, Snapshots and Undo" width="100%"></p>

## Quick start

1. **[Download `Swarlex-Manager.bat`](https://github.com/swarlex/SwarlexManager/releases/latest/download/Swarlex-Manager.bat)**
   and put it in a folder of its own, for example `Documents\Swarlex`.
2. **Double-click it.** If SmartScreen warns about a downloaded script, choose *More info > Run anyway*.
3. **Pick your app.** `1` Discord, `2` Spotify or `3` Steam, then `1` again to install its mod (Vencord,
   Spicetify or Millennium). Swarlex fetches whatever it needs - Git, Node.js and the mod itself - on the way.

From then on Swarlex keeps itself up to date. When a Discord, Spotify or Steam update breaks a mod, open
**[6] Repair** and press Enter.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/discord.svg" alt="Discord and Vencord menu"><br><sub><b>Discord &amp; Vencord</b></sub></td>
    <td align="center"><img src="docs/spotify.svg" alt="Spotify and Spicetify menu"><br><sub><b>Spotify &amp; Spicetify</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/steam.svg" alt="Steam and Millennium menu"><br><sub><b>Steam &amp; Millennium</b></sub></td>
    <td align="center"><img src="docs/settings.svg" alt="Settings menu"><br><sub><b>Settings</b></sub></td>
  </tr>
</table>

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

<p align="center"><img src="docs/repair.svg" alt="One-click Repair" width="660"></p>

- **App Updater** - lists every app with a pending update through `winget` and upgrades them one by one.
- **Backup & restore** - one `.zip` with your Vencord settings, userplugins, Spicetify and Millennium data.
- **Safety snapshots** - taken automatically before every update; *Backup > Undo Last Update* rolls back,
  including the Vencord source itself.
- **One-click Repair** - finds and fixes what client updates tend to break: a Discord update that removed
  Vencord, a Spotify update that removed Spicetify, a Steam update that removed Millennium's loader, stuck git
  state, leftover temp files and more.
- **Self-update** - checks this repository on start and keeps itself up to date, automatically or after
  asking you first.
- **Logs & history**, **system info** for troubleshooting, optional **start as administrator**.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in)
- An internet connection for installs and updates
- `winget` (*App Installer* from the Microsoft Store) - used to install Git and Node.js automatically
  when Vencord needs them, and by the App Updater

Nothing else needs to be installed by hand. Administrator rights are **not** required.

## Installation

1. Download **`Swarlex-Manager.bat`** from the [latest release](https://github.com/swarlex/SwarlexManager/releases/latest).
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

Swarlex looks for a new version every time it starts. The check takes a moment, is silent when there is
nothing new, and is skipped when you are offline.

- **Auto-Update on** (the default): a new version is installed as soon as you open Swarlex, before anything
  else runs - Swarlex downloads it, verifies its SHA-256, swaps itself and reopens.
- **Auto-Update off** (*Settings > [9]*): the *Settings* entry on the main menu announces the new version,
  and *Settings > [8] Swarlex Update* shows what changed and installs it when you confirm.

An update that cannot be verified is never installed. The previous version is kept as
`%APPDATA%\Swarlex Manager\Swarlex-Manager.previous.bat`.

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
installed copy then installs the update the next time it is opened.

## FAQ

<details>
<summary><b>Is it safe? What does it download?</b></summary>

Swarlex is a plain-text script, so you can read every line of it before you run it. It downloads only from
the official sources: Vencord and Spicetify from their GitHub repositories, Millennium from its GitHub
releases (checked against the published SHA-256 and the publisher's code signature), Git and Node.js through
`winget`, pnpm through `npm`, userplugins only from links you paste, and its own updates from this repository
(checked against the release's SHA-256). It never asks for
or reads your Discord, Spotify or Steam login.
</details>

<details>
<summary><b>Windows SmartScreen or my antivirus warns about it.</b></summary>

SmartScreen warns about most scripts downloaded from the internet that few people have run yet. Choose
*More info > Run anyway*. Some antivirus programs are suspicious of any `.bat` file that patches other apps;
compare your file's SHA-256 with the release (see [Verifying a download](#verifying-a-download)) if in doubt.
</details>

<details>
<summary><b>Do I need administrator rights?</b></summary>

No. Everything works with standard rights. *Settings > [3] Start As Admin* is there for setups where Discord,
Spotify or Steam lives in a folder your Windows account cannot write to.
</details>

<details>
<summary><b>Discord, Spotify or Steam updated and my mods are gone.</b></summary>

That is what client updates do. Open **[6] Repair**: it finds the client that lost its mod and puts it back
in one go. For Spotify you can also turn on **Spotify > [3] Update Guard** so it stops updating itself.
</details>

<details>
<summary><b>How do I remove everything again?</b></summary>

*Discord > [6] Uninject*, *Spotify > [5] Restore Spotify* and *Steam > [6] Uninstall* put each client back to
stock. Then delete `Swarlex-Manager.bat` and the `%APPDATA%\Swarlex Manager` folder.
</details>

<details>
<summary><b>Something does not work.</b></summary>

[Open an issue](https://github.com/swarlex/SwarlexManager/issues/new/choose) and paste
*Settings > [7] System Info* - it lists every version Swarlex sees and answers most questions up front.
</details>

## Contributing

Bug reports, ideas and pull requests are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md) for how the script
is put together and what keeps it working everywhere. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Disclaimer

Swarlex Manager is an independent project and is not affiliated with or endorsed by Discord, Spotify,
Valve, Vencord, Spicetify or Millennium. Client modifications may be against those services' terms of
service. Use it at your own risk.

## Credits

Swarlex Manager is made by [swarlex](https://github.com/swarlex), built together with [Claude](https://claude.ai) by Anthropic
in [Claude Code](https://claude.com/claude-code).

It stands on the shoulders of [Vencord](https://github.com/Vendicated/Vencord), [Spicetify](https://github.com/spicetify/cli),
[Millennium](https://github.com/SteamClientHomebrew/Millennium) and [winget](https://github.com/microsoft/winget-cli).

## License

Swarlex Manager is free software, released under the [GNU General Public License v3.0](LICENSE) or (at your
option) any later version.
