# Changelog

All notable changes to Swarlex Manager are listed here. Versions follow [Semantic Versioning](https://semver.org).

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
