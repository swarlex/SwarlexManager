# Static checks for Swarlex-Manager.bat, run by the Build workflow on every push and pull request.
# Runs on Windows PowerShell 5.1 - the same PowerShell the embedded blocks run on for users.
param([string]$Path = 'Swarlex-Manager.bat', [string]$Changelog = 'docs\CHANGELOG.md', [string]$Tag = '')
$ErrorActionPreference = 'Stop'
$failed = 0
function Pass([string]$msg) { Write-Host "  [ok]   $msg" -ForegroundColor Green }
function Fail([string]$msg) { Write-Host "  [fail] $msg" -ForegroundColor Red; $script:failed++ }

$bytes = [IO.File]::ReadAllBytes($Path)
$text = [Text.Encoding]::UTF8.GetString($bytes)
Write-Host "Checking $Path ($([math]::Round($bytes.Length / 1KB)) KB)"

# 1. cmd.exe misreads labels in a file with LF line endings
$bare = ([regex]::Matches($text, "(?<!`r)`n")).Count
if ($bare -eq 0) { Pass 'CRLF line endings' } else { Fail "$bare line(s) end in LF instead of CRLF" }

# 2. The version is set once and has a changelog entry
$ver = [regex]::Matches($text, '(?m)^set "SWX_VERSION=([0-9]+\.[0-9]+\.[0-9]+)"\r?$')
if ($ver.Count -ne 1) { Fail "expected one 'set ""SWX_VERSION=x.y.z""' line, found $($ver.Count)" }
else {
    $v = $ver[0].Groups[1].Value
    Pass "version $v"
    if ((Test-Path $Changelog) -and ([IO.File]::ReadAllText($Changelog) -match ('(?m)^## ' + [regex]::Escape($v) + '\s*$'))) { Pass "docs/CHANGELOG.md has a '## $v' section" }
    else { Fail "docs/CHANGELOG.md has no '## $v' section" }
    # a release tag must name the version the script carries, or installed copies would never see it as new
    if ($Tag) { if ($Tag -eq "v$v") { Pass "tag $Tag matches" } else { Fail "tag $Tag does not match SWX_VERSION $v" } }
}

# 3. Every embedded PowerShell block parses on PowerShell 5.1
$blocks = [regex]::Matches($text, '(?s)::SWX_PS_BEGIN (\w+)\r?\n(.*?)::SWX_PS_END')
$names = @{}
$psErrors = 0
foreach ($b in $blocks) {
    $name = $b.Groups[1].Value
    if ($names.ContainsKey($name)) { Fail "PowerShell block $name exists twice" }
    $names[$name] = $true
    $errs = $null
    [Management.Automation.PSParser]::Tokenize($b.Groups[2].Value, [ref]$errs) | Out-Null
    foreach ($e in $errs) { Fail ("block {0}, line {1}: {2}" -f $name, $e.Token.StartLine, $e.Message); $psErrors++ }
}
if ($psErrors -eq 0) { Pass "$($blocks.Count) PowerShell blocks parse on PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" }
foreach ($m in [regex]::Matches($text, 'RUN_PS ([A-Z_]+)')) {
    if (-not $names.ContainsKey($m.Groups[1].Value)) { Fail "RUN_PS $($m.Groups[1].Value) - no such block" }
}
if (-not $names.ContainsKey('COMMON')) { Fail 'the COMMON block is missing' }

# 4. Every call/goto target exists (batch part only, outside the PowerShell blocks; targets built from a
#    variable, like :REPAIR_FIX_!ID!, are left out)
$batch = [regex]::Replace($text, '(?s)::SWX_PS_BEGIN \w+\r?\n.*?::SWX_PS_END', '')
$labels = @{}
foreach ($m in [regex]::Matches($batch, '(?m)^:([A-Za-z0-9_]+)\s*$')) { $labels[$m.Groups[1].Value.ToUpper()] = $true }
$missing = @{}
foreach ($m in [regex]::Matches($batch, '(?im)\b(?:call\s+:|goto\s+:?)([A-Za-z0-9_]+)(?![A-Za-z0-9_!%])')) {
    $l = $m.Groups[1].Value.ToUpper()
    if ($l -eq 'EOF') { continue }
    if (-not $labels.ContainsKey($l)) { $missing[$l] = $true }
}
if ($missing.Count -eq 0) { Pass "$($labels.Count) labels, every call/goto target exists" }
else { foreach ($l in $missing.Keys) { Fail "call/goto target :$l does not exist" } }

Write-Host ''
if ($failed) { Write-Host "$failed check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
exit 0
