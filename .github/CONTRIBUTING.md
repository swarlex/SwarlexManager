# Contributing to Swarlex Manager

Thanks for wanting to help. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open a bug report](https://github.com/swarlex/SwarlexManager/issues/new?template=bug_report.yml) and paste
*Settings > [7] System Info* (press **C** to copy it). It lists every version Swarlex sees - Windows, Discord,
Vencord, Spotify, Spicetify, Steam, Millennium, Git, Node.js - and answers most questions before they are asked.

Security problems go through [private vulnerability reporting](SECURITY.md), not public issues.

## Changing the script

Swarlex Manager is one file, `Swarlex-Manager.bat`. The batch part draws the menus; the heavier work is done
by PowerShell blocks embedded in the same file between `::SWX_PS_BEGIN <NAME>` and `::SWX_PS_END`, which
`:RUN_PS <NAME>` runs.

A few rules keep it working on every Windows 10 and 11 machine:

- **CRLF line endings.** `cmd.exe` misreads labels in a file with LF endings. `.gitattributes` takes care of
  this in git; check your editor does not convert the file.
- **Windows PowerShell 5.1.** The embedded blocks must run on the PowerShell that ships with Windows - no
  PowerShell 7 syntax such as `??`, `?.` or ternaries.
- **No administrator rights needed.** Anything that only works elevated needs a clear message when it is not.
- **The 64-column card.** Menus and messages are laid out for a 64-character-wide card; keep new lines inside it.
- **Undo first.** Anything that changes Discord, Spotify or Steam files must leave a way back
  (a backup, a snapshot or an uninstall option).

The **Build** check runs on every push and pull request and catches the mechanical mistakes: lost CRLF
endings, a PowerShell block that no longer parses, a `call`/`goto` to a label that does not exist, or a
version without a changelog entry. Run it locally with `powershell -File .github\scripts\check.ps1`.

Test your change by running the script: open every menu you touched, and try the failure paths too
(no internet, the app not installed, the app running).

## Pull requests

1. Fork the repository and create a branch.
2. Make your change and describe it in [docs/CHANGELOG.md](../docs/CHANGELOG.md), under `### Added`, `### Changed`
   or `### Fixed` of a new `## Unreleased` section.
3. Open a pull request describing what changed and how you tested it.

Do not change `SWX_VERSION` - the version is bumped when a release is made.

## Making a release (maintainers)

1. Write the version's section at the top of [docs/CHANGELOG.md](../docs/CHANGELOG.md): `## x.y.z`, an optional
   one-line summary, then `### Added` / `### Changed` / `### Fixed`. This becomes the release notes.
2. Run, from `main`:

   ```powershell
   .\tools\release.ps1 -Notes "Short summary"                 # 1.1.8 -> 1.1.9
   .\tools\release.ps1 -Version 1.2.0 -Notes "Short summary"
   ```

[tools/release.ps1](../tools/release.ps1) raises `SWX_VERSION`, runs the Build checks, commits on a branch
`vx.y.z`, merges it into `main` by pull request and publishes the release with `Swarlex-Manager.bat` and its
`.sha256` (GitHub CLI, signed in). GitHub Actions then checks the tag ([build.yml](workflows/build.yml)) and
scans the release on VirusTotal ([virustotal.yml](workflows/virustotal.yml)). Every installed copy installs
the update the next time it is opened.

## License

By contributing you agree that your contribution is released under the
[GNU General Public License v3.0 or later](../LICENSE), like the rest of the project.
