# Changelog

All notable changes to Swarlex Manager are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.1.8] - 2026-10-05

- Faster start: the update check reads the latest version with Windows' built-in `curl` and only starts
  PowerShell when there is something to install (about 0.2 s saved on every start).
- Faster Discord and Spotify menus: Git, Node.js, pnpm and the Spicetify CLI are looked up once per
  session instead of on every visit.

## [1.1.7] - 2026-10-04

- Restore now brings your Spotify setup back for real: Spicetify is applied right after the restore, so the
  restored themes and extensions show up. Spotify's location and Spicetify's backup info keep this PC's
  values instead of the ones from the PC the backup was made on, which stopped Spicetify from applying.
- When the backup has Millennium add-ons but Millennium is not installed, Restore offers to install it.
- Userplugins in a backup restored before Vencord is set up are no longer skipped: they are kept and put
  in place by *Discord > Patch Discord*.

## [1.1.6] - 2026-10-04

- Fixed "pnpm is not installed and could not be installed automatically" on PCs without pnpm. Node.js
  also installs `npm.ps1`, which Swarlex picked and could not start; it now always runs the real program.
  The same fix covers `pnpm install` when pnpm itself came from npm.
- If npm cannot install pnpm, Swarlex installs it with `winget` instead.

## [1.1.5] - 2026-10-04

- The repository is now [swarlex/SwarlexManager](https://github.com/swarlex/SwarlexManager). Update checks
  follow a renamed repository by themselves, so older copies keep finding new versions.

## [1.1.4] - 2026-10-04

- Auto-Update installs a new version the first time Swarlex is opened after its release. Before, one start
  only noticed it and the next start installed it. The check is silent and skipped when you are offline.
- Release notes in *Swarlex Update* no longer show markdown leftovers or the checksum line, and the
  update message fits the window.

## [1.1.3] - 2026-10-04

- Fixed "Could not reach GitHub: (403) Forbidden". The GitHub API allows only 60 calls an hour per
  internet address; update checks now read the version from the normal GitHub website, which has no such
  limit, and downloads still work when the API limit is used up.

## [1.1.2] - 2026-10-04

- Every screen lines up: the Discord status grid and the Backup menu were one column off.
- Messages that ran past the edge of the card (mostly warnings and errors) were shortened.
- System Info shows the Swarlex version, so bug reports say which version they are about.

## [1.1.1] - 2026-10-04

- Fixed: after an update reopened Swarlex, closing it left the window open at a command prompt. Swarlex
  now closes such a window itself, and updates reopen it the same way a double-click does. A terminal you
  opened yourself is still left open.

## [1.1.0] - 2026-10-04

- Automatic updates: with the new *Settings > [9] Auto-Update* option (on by default) a new Swarlex
  version is installed at start, before anything else runs, and Swarlex reopens as the new version.
  Turn it off to be asked first, as before.
- An update that was just installed is no longer announced again until the next background check.

## [1.0.0] - 2026-10-04

First public release.

- Discord & Vencord: build and patch every Discord build, update, Plugin Hub with automatic detection of
  plugins that break the build, QuickCSS, cache cleaning, uninject.
- Spotify & Spicetify: apply, update, Update Guard against Spotify auto-updates, cache cleaning, restore.
- Steam & Millennium: verified install and update (SHA-256 plus code signature), add-on manager, cache
  cleaning, uninstall that keeps your add-ons.
- App Updater for every app with a pending `winget` update.
- Full backup and restore, plus automatic safety snapshots with Undo Last Update.
- One-click Repair for what client updates tend to break.
- Self-update from GitHub releases, verified by SHA-256.
- Action history, detailed log, system info, optional start as administrator.
