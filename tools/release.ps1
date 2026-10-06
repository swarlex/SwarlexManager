# SPDX-License-Identifier: GPL-3.0-or-later
<#
.SYNOPSIS
  One command from local change to GitHub: every installed copy then installs the update the next time it
  is opened.

  1. raises SWX_VERSION in Swarlex-Manager.bat (patch by default, or -Version X.Y.Z)
  2. runs the Build checks (.github\scripts\check.ps1) and writes dist\Swarlex-Manager.bat + its .sha256
  3. commits every change on a branch vX.Y.Z, opens a pull request and merges it into main
     (main's history then shows one "Merge pull request #N" per release)
  4. creates the GitHub release vX.Y.Z with the script and its checksum (GitHub CLI "gh", signed in)

  The release text is this version's section of docs\CHANGELOG.md (a short summary, then ### Added /
  ### Changed / ### Fixed); -Notes is the commit message and the text when there is no such section.

.EXAMPLE
  .\tools\release.ps1 -Notes "Faster start"                      # 1.1.8 -> 1.1.9
  .\tools\release.ps1 -Version 1.2.0 -Notes "Vesktop support"
#>
param(
    [string]$Version,
    [Parameter(Mandatory)] [string]$Notes,
    [string]$Repo = 'swarlex/SwarlexManager',
    [switch]$ByClaude          # adds the Co-Authored-By trailer to the commit
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$bat = Join-Path $root 'Swarlex-Manager.bat'

$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh -and (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe")) { $gh = "$env:ProgramFiles\GitHub CLI\gh.exe" }
if (-not $gh) { throw 'GitHub CLI (gh) not found. Install it with: winget install GitHub.cli, then: gh auth login' }
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not signed in: gh auth login --web' }
# Pushes go through gh's sign-in, whatever git's own credential settings are. git runs the helper through
# a shell, where a path with spaces would be cut apart - so gh's folder goes on PATH and the helper is "gh".
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { $env:PATH = (Split-Path $gh) + ';' + $env:PATH }
$git = @('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential')

if ((git rev-parse --abbrev-ref HEAD) -ne 'main') { throw 'Run this from the main branch.' }
git fetch -q origin
if ((git rev-list --count HEAD..origin/main) -ne '0') { throw 'main is behind GitHub: git pull first.' }

# 1. version - kept in Swarlex-Manager.bat itself, which the update check compares against
$text = [IO.File]::ReadAllText($bat)
$m = [regex]::Match($text, '(?m)^set "SWX_VERSION=(\d+\.\d+\.\d+)"\r?$')
if (-not $m.Success) { throw 'set "SWX_VERSION=x.y.z" not found in Swarlex-Manager.bat' }
$cur = [version]$m.Groups[1].Value
if (-not $Version) { $Version = "$($cur.Major).$($cur.Minor).$($cur.Build + 1)" }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must be X.Y.Z: $Version" }
if ([version]$Version -le $cur) { throw "The new version ($Version) must be greater than the current one ($cur)" }
$setVersion = {
    param($v)
    $t = [IO.File]::ReadAllText($bat)
    $t = [regex]::Replace($t, '(?m)^set "SWX_VERSION=\d+\.\d+\.\d+"(?=\r?$)', "set `"SWX_VERSION=$v`"")
    [IO.File]::WriteAllText($bat, $t, (New-Object Text.UTF8Encoding $false))
}
& $setVersion $Version

# 2. checks (a failed check stops here: nothing is pushed or published)
$log = Join-Path $root 'docs\CHANGELOG.md'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root '.github\scripts\check.ps1') -Path $bat -Changelog $log
if ($LASTEXITCODE -ne 0) { & $setVersion "$cur"; throw 'Checks failed, nothing was published.' }
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Copy-Item -LiteralPath $bat -Destination $dist -Force
$file = Join-Path $dist 'Swarlex-Manager.bat'
$sha = "$file.sha256"
$hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText($sha, "$hash  Swarlex-Manager.bat`n")

# 3. commit on a release branch, pull request, merge into main
$msg = "v$Version`: $Notes"
if ($ByClaude) { $msg += "`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" }
# git writes harmless notes (e.g. line-ending warnings) to stderr; only exit codes count from here on
$ErrorActionPreference = 'Continue'
$branch = "v$Version"
git checkout -q -B $branch
git add -A
git commit -q -m $msg
if ($LASTEXITCODE -ne 0) { git checkout -q main; throw 'git commit failed' }
git @git push -q -u origin $branch
if ($LASTEXITCODE -ne 0) { throw "git push failed - the change is committed on branch $branch (git checkout main, then git reset --soft main to undo)" }
& $gh pr create --repo $Repo --base main --head $branch --title "Release v$Version" --body $Notes
if ($LASTEXITCODE -ne 0) { git checkout -q main; throw 'gh pr create failed' }
& $gh pr merge $branch --repo $Repo --merge --delete-branch
if ($LASTEXITCODE -ne 0) { git checkout -q main; throw 'gh pr merge failed (the pull request is open; merge it on GitHub)' }
git checkout -q main
git @git pull -q --ff-only origin main
git branch -q -D $branch 2>$null

# 4. GitHub release (the tag is created on the merged commit)
$body = $Notes
if (Test-Path -LiteralPath $log) {
    $s = [regex]::Match([IO.File]::ReadAllText($log), "(?ms)^## $([regex]::Escape($Version))\s*\r?\n(.*?)(?=^## |\z)")
    if ($s.Success -and $s.Groups[1].Value.Trim()) { $body = $s.Groups[1].Value.Trim() }
}
$notesFile = Join-Path ([IO.Path]::GetTempPath()) "swarlexmanager-notes-$Version.md"
$footer = "`n`n---`nDownload **Swarlex-Manager.bat** and double-click it. Installed copies update themselves (*Settings > [9] Auto-Update*)."
[IO.File]::WriteAllText($notesFile, $body + $footer, (New-Object Text.UTF8Encoding $false))
& $gh release create "v$Version" $file $sha --repo $Repo --target main --title "Swarlex Manager $Version" --notes-file $notesFile
Remove-Item -LiteralPath $notesFile -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed (the code was pushed, the release was not created)' }
Write-Host "Published: v$Version  https://github.com/$Repo/releases/tag/v$Version"
Write-Host 'Installed copies install it the next time they are opened (Settings > [9] Auto-Update).'
