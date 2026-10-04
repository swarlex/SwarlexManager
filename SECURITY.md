# Security

## Reporting a problem

Please report security problems **privately** through
[GitHub's private vulnerability reporting](https://github.com/swarlex/SwarlexManager/security/advisories/new),
not as a public issue. You will get an answer as soon as possible, and a fixed release reaches every
installed copy through the built-in updater.

## How Swarlex protects you

- **Updates of Swarlex itself** are only installed after their SHA-256 matches the checksum published
  with the same GitHub release, and the file is confirmed to be Swarlex at the announced version.
- **Millennium** is only installed after its download matches the release's SHA-256 and every `.dll` and
  `.exe` in it carries a valid code signature from Millennium's signer.
- **Vencord, Spicetify, Git, Node.js and pnpm** come from their official sources (GitHub, the official
  install script, `winget`, `npm`).
- Swarlex needs **no administrator rights** and stores nothing outside `%APPDATA%\Swarlex Manager`,
  your Desktop backups and the folders of the apps it manages.

## Supported versions

Only the [latest release](https://github.com/swarlex/SwarlexManager/releases/latest) receives fixes. With
Auto-Update on (the default) you are always on it.
