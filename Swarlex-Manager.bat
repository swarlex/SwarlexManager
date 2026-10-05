@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =============================================================
:: SWARLEX MANAGER - CONTROL CENTER
:: https://github.com/swarlex/SwarlexManager
::
:: Copyright (C) 2026 swarlex
:: This program is free software: you can redistribute it and/or modify it under the terms of
:: the GNU General Public License as published by the Free Software Foundation, either version 3
:: of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY;
:: see the LICENSE file or <https://www.gnu.org/licenses/gpl-3.0.html> for details.
:: =============================================================

cd /d "%~dp0"
:: <nul: chcp swallows redirected input, which would break piping keys into Swarlex
chcp 65001 >nul <nul
set "SWX_SELF=%~f0"
set "SWX_SELF_NAME=%~nx0"
:: Bump SWX_VERSION for every release; the release workflow refuses a tag that does not match it
set "SWX_VERSION=1.1.8"
set "SWX_REPO=swarlex/SwarlexManager"
set "SWX_BASE_PATH=%PATH%"
set "GIT_TERMINAL_PROMPT=0"
set "SWX_UPDATE_FILE=%TEMP%\swarlex-updates.txt"
set "SWX_BUILD_LOG=%TEMP%\swarlex-build.log"
set "SWX_INSTALL_LOG=%TEMP%\swarlex-install.log"
set "SWX_REPAIR_FILE=%TEMP%\swarlex-repair.txt"
set "SWX_DATA=%APPDATA%\Swarlex Manager"
set "SWX_SETTINGS=%APPDATA%\Swarlex Manager\settings.ini"
if not exist "%SWX_DATA%\" (
    if exist "%APPDATA%\Swarlex\" (
        move "%APPDATA%\Swarlex" "%SWX_DATA%" >nul 2>&1
    )
)
set "SWX_LOGFILE=%SWX_DATA%\swarlex.log"

:: An elevated relaunch (see :ELEVATE) passes --elevated first; "shift /1" keeps %0 intact
set "SWX_ELEVATED_RUN="
if /i "%~1"=="--elevated" set "SWX_ELEVATED_RUN=1"
if defined SWX_ELEVATED_RUN shift /1
set "SWX_ARG1=%~1"
set "SWX_LOADER=$f = [IO.File]::ReadAllText($env:SWX_SELF, [Text.Encoding]::UTF8); function Get-Block($n) { $m = '::SWX_PS' + '_BEGIN ' + $n; $i = $f.IndexOf($m); if ($i -lt 0) { exit 197 }; $s = $i + $m.Length; $f.Substring($s, $f.IndexOf('::SWX_PS' + '_END', $s) - $s) }; & ([ScriptBlock]::Create((Get-Block 'COMMON') + (Get-Block $env:SWX_PS_BLOCK)))"

:: -------------------------------------------------------------
:: 1. FAST NATIVE ANSI ESCAPE COLORS & CURSOR CONTROL (~15ms)
:: -------------------------------------------------------------
for /F "tokens=1,2 delims=#" %%E in ('"prompt #$H#$E# & echo on & for %%i in (1) do rem"') do set "ESC=%%F"
set "C_RESET=!ESC![0m"
set "C_BOLD=!ESC![1m"
set "C_CYAN=!ESC![96m"
set "C_GREEN=!ESC![92m"
set "C_YELLOW=!ESC![93m"
set "C_RED=!ESC![91m"
set "C_WHITE=!ESC![97m"
set "C_GRAY=!ESC![90m"
set "C_MAGENTA=!ESC![95m"
set "C_BLUE=!ESC![94m"

:: Calculate dynamic centering padding based on current window size
call :CALC_CENTER

:: -------------------------------------------------------------
:: 2. PRIVILEGE AND ENVIRONMENT DETECTION
:: -------------------------------------------------------------
fltmc >nul 2>&1
if errorlevel 1 (
    set "IS_ADMIN=0"
    set "ADMIN_TAG=[Standard]"
    set "SPICETIFY_FLAGS="
    set "PRIV_DOT=!C_WHITE!●!C_RESET!"
    set "PRIV_TXT=!C_WHITE!Standard      !C_RESET!"
) else (
    set "IS_ADMIN=1"
    set "ADMIN_TAG=[Administrator]"
    set "SPICETIFY_FLAGS=--bypass-admin"
    set "PRIV_DOT=!C_MAGENTA!●!C_RESET!"
    set "PRIV_TXT=!C_MAGENTA!Administrator !C_RESET!"
)

title Swarlex Manager !ADMIN_TAG!

:: qprocess lists processes ~5x faster than tasklist but does not ship with Windows Home
set "SWX_QPROC="
if exist "%SystemRoot%\System32\qprocess.exe" set "SWX_QPROC=1"

:: -------------------------------------------------------------
:: 3. PATH AND BASE DIRECTORIES
:: -------------------------------------------------------------
call :REFRESH_PATH
call :DETECT_PATHS
call :LOAD_SETTINGS
call :LOG_INIT

:: CLI Arguments Support
set "CLI_MODE="
if /i "%~1"=="backup" set "CLI_MODE=1" & goto ACTION_BACKUP_PROFILE
if /i "%~1"=="restore" set "CLI_MODE=1" & goto ACTION_RESTORE_PROFILE
if /i "%~1"=="patch" set "CLI_MODE=1" & goto ACTION_BUILD_AND_INJECT
if /i "%~1"=="apply" set "CLI_MODE=1" & goto ACTION_SPICETIFY_APPLY
if /i "%~1"=="repair" set "CLI_MODE=1" & goto ACTION_REPAIR
if /i "%~1"=="millennium" set "CLI_MODE=1" & goto ACTION_MILL_INSTALL

:: "Start As Admin" setting. If UAC is declined Swarlex simply carries on with standard rights.
if /i "!CFG_ADMIN!"=="on" if "!IS_ADMIN!"=="0" if not defined SWX_ELEVATED_RUN (
    call :ELEVATE "%~1"
    if not errorlevel 1 goto SWX_QUIT
)

:: "Auto-Update" setting: a newer release found by an earlier start is installed now, before anything
:: else runs, and Swarlex restarts as the new version. If it cannot be verified, Swarlex just carries on.
if /i "!CFG_AUTOUPD!"=="on" call :AUTO_SELF_UPDATE && goto SWX_QUIT

set "UPD_HAD_RESULT="
if exist "!SWX_UPDATE_FILE!" set "UPD_HAD_RESULT=1"
call :START_UPDATE_CHECK
if not defined UPD_HAD_RESULT call :WAIT_UPDATE_CHECK
if /i "%~1"=="vencord" goto ROUTE_VENCORD
if /i "%~1"=="discord" goto ROUTE_VENCORD
if /i "%~1"=="spicetify" goto ROUTE_SPICETIFY
if /i "%~1"=="spotify" goto ROUTE_SPICETIFY
if /i "%~1"=="steam" goto MENU_STEAM
if /i "%~1"=="settings" goto MENU_SETTINGS

:: Play one-time startup animation on fresh launch
if not defined SHOWN_INTRO (
    set "SHOWN_INTRO=1"
    if /i not "!CFG_INTRO!"=="off" call :PLAY_INTRO
)

goto MAIN_MENU

:: -------------------------------------------------------------
:: DYNAMIC CENTERING SUBROUTINE
:: -------------------------------------------------------------
:CALC_CENTER
set "COLS=100"
:: ^<nul: without it "mode con" drains the batch's stdin, which breaks piped/automated input
for /f "tokens=2 delims=:" %%A in ('mode con ^<nul 2^>nul ^| findstr /i "Columns"') do (
    set /a "COLS=%%A"
)
set "CARD_WIDTH=64"
set /a "PAD=(COLS - CARD_WIDTH) / 2"
if !PAD! lss 2 set "PAD=2"
if !PAD! gtr 45 set "PAD=45"
set "INDENT="
for /l %%i in (1,1,!PAD!) do set "INDENT=!INDENT! "
set "PROMPT_INDENT=!C_RESET!!INDENT!  "
exit /b 0

:: -------------------------------------------------------------
:: BASE SUBROUTINES AND PATH DETECTION
:: -------------------------------------------------------------
:REFRESH_PATH
:: Rebuilt from the original PATH every time so repeated calls never grow it past cmd's limit
set "PATH=%LOCALAPPDATA%\pnpm\bin;%LOCALAPPDATA%\pnpm;%APPDATA%\npm;%LOCALAPPDATA%\Microsoft\WinGet\Links;%ProgramFiles%\nodejs;%LOCALAPPDATA%\Programs\nodejs;%ProgramFiles%\Git\cmd;%LOCALAPPDATA%\Programs\Git\cmd;%LOCALAPPDATA%\spicetify;%APPDATA%\spicetify;!SWX_BASE_PATH!"
if defined PNPM_HOME set "PATH=!PNPM_HOME!\bin;!PNPM_HOME!;!PATH!"
exit /b 0

:DETECT_PATHS
:: Shell folder values are REG_EXPAND_SZ (e.g. %USERPROFILE%\Documents); "call set" expands them
set "USER_DOCS="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Personal 2^>nul ^| findstr /i "REG_"') do call set "USER_DOCS=%%b"
if not defined USER_DOCS set "USER_DOCS=%USERPROFILE%\Documents"
if not exist "!USER_DOCS!\" set "USER_DOCS=%USERPROFILE%\Documents"
if "!USER_DOCS:~-1!"=="\" set "USER_DOCS=!USER_DOCS:~0,-1!"

set "DESK_DIR="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop 2^>nul ^| findstr /i "REG_"') do call set "DESK_DIR=%%b"
if not defined DESK_DIR set "DESK_DIR=%USERPROFILE%\Desktop"
if not exist "!DESK_DIR!\" set "DESK_DIR=%USERPROFILE%\Desktop"
if "!DESK_DIR:~-1!"=="\" set "DESK_DIR=!DESK_DIR:~0,-1!"

set "VENCORD_DIR=!USER_DOCS!\Vencord"
for %%P in ("%USERPROFILE%\Documents\Vencord" "%USERPROFILE%\OneDrive\Documents\Vencord" "%USERPROFILE%\Belgeler\Vencord" "!USER_DOCS!\Vencord" "%~dp0.") do (
    if exist "%%~fP\package.json" if exist "%%~fP\scripts\build\build.mjs" set "VENCORD_DIR=%%~fP"
)

:: Steam stores its folder with forward slashes (c:/program files (x86)/steam)
set "STEAM_DIR="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| findstr /i "REG_"') do set "STEAM_DIR=%%b"
if defined STEAM_DIR set "STEAM_DIR=!STEAM_DIR:/=\!"
if not defined STEAM_DIR set "STEAM_DIR=%ProgramFiles(x86)%\Steam"
if not exist "!STEAM_DIR!\steam.exe" if exist "%ProgramFiles(x86)%\Steam\steam.exe" set "STEAM_DIR=%ProgramFiles(x86)%\Steam"
set "SWX_STEAM_DIR=!STEAM_DIR!"

set "SPOTIFY_DIR=%APPDATA%\Spotify"
set "IS_STORE_SPOTIFY=0"
if not exist "%SPOTIFY_DIR%\Spotify.exe" (
    if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\Spotify.exe" (
        set "SPOTIFY_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps"
        set "IS_STORE_SPOTIFY=1"
    )
)
exit /b 0

:RUN_PS
:: Runs an embedded PowerShell block (see the end of this file). Arg: block name.
set "SWX_PS_BLOCK=%~1"
set "SWX_PAD=!PAD!"
set "SWX_VENCORD_DIR=!VENCORD_DIR!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "!SWX_LOADER!"
set "PS_RC=!errorlevel!"
:: Script errors are logged by the blocks themselves (Say); these two mean the block never ran.
:: 197 is the loader's own code - no block may use it (REPAIRSCAN returns its problem count, up to 99)
if "!PS_RC!"=="197" call :DLOG ERROR "Embedded script block %~1 is missing from Swarlex-Manager.bat"
if !PS_RC! GEQ 9000 call :DLOG ERROR "Could not start PowerShell for %~1 [code !PS_RC!]"
exit /b !PS_RC!

:START_UPDATE_CHECK
:: Runs in the background so menus never wait on the network; DETECT_STATUS reads the result file.
:: The previous result stays visible until the new one replaces it (UPDATECHECK swaps the file in one
:: move). Arg "fresh" drops it first - used right after an update so a stale "update available" never shows.
if /i "%~1"=="fresh" del /f /q "!SWX_UPDATE_FILE!" >nul 2>&1
set "SWX_PS_BLOCK=UPDATECHECK"
set "SWX_VENCORD_DIR=!VENCORD_DIR!"
start "" /b cmd /d /s /c "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "!SWX_LOADER!" <nul >nul 2>&1"
exit /b 0

:WAIT_UPDATE_CHECK
:: First start only (no earlier result): wait up to ~4 s so the first menu can already show updates.
:: ping is the delay because timeout fails when input is redirected.
for /l %%i in (1,1,4) do (
    if exist "!SWX_UPDATE_FILE!" exit /b 0
    ping -n 2 127.0.0.1 >nul 2>&1
)
exit /b 0

:LOAD_SETTINGS
set "CFG_INTRO=on"
set "CFG_RELAUNCH=ifopen"
set "CFG_ADMIN=off"
set "CFG_AUTOUPD=on"
if exist "%SWX_SETTINGS%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%SWX_SETTINGS%") do (
        if /i "%%A"=="intro" set "CFG_INTRO=%%B"
        if /i "%%A"=="relaunch" set "CFG_RELAUNCH=%%B"
        if /i "%%A"=="admin" set "CFG_ADMIN=%%B"
        if /i "%%A"=="autoupdate" set "CFG_AUTOUPD=%%B"
    )
)
:: A hand-edited or damaged value falls back to the default instead of confusing the menus
if /i not "!CFG_INTRO!"=="off" set "CFG_INTRO=on"
if /i not "!CFG_RELAUNCH!"=="always" if /i not "!CFG_RELAUNCH!"=="never" set "CFG_RELAUNCH=ifopen"
if /i not "!CFG_ADMIN!"=="on" set "CFG_ADMIN=off"
if /i not "!CFG_AUTOUPD!"=="off" set "CFG_AUTOUPD=on"
exit /b 0

:SAVE_SETTINGS
if not exist "%SWX_DATA%\" mkdir "%SWX_DATA%" 2>nul
> "%SWX_SETTINGS%" (
    echo intro=!CFG_INTRO!
    echo relaunch=!CFG_RELAUNCH!
    echo admin=!CFG_ADMIN!
    echo autoupdate=!CFG_AUTOUPD!
)
exit /b 0

:: -------------------------------------------------------------
:: LOGGING
:: history.log = one line per action (Settings > Action History)
:: swarlex.log = detailed log: sessions, actions, warnings and errors (Settings > Log File)
:: -------------------------------------------------------------
:LOG_INIT
if not exist "%SWX_DATA%\" mkdir "%SWX_DATA%" 2>nul
:: swarlex.log rolls over to swarlex.old.log at 1 MB; history.log is trimmed to its last 500 lines at 256 KB
if exist "!SWX_LOGFILE!" for %%L in ("!SWX_LOGFILE!") do if %%~zL GTR 1048576 move /y "!SWX_LOGFILE!" "!SWX_DATA!\swarlex.old.log" >nul 2>&1
if exist "!SWX_DATA!\history.log" for %%L in ("!SWX_DATA!\history.log") do if %%~zL GTR 262144 call :RUN_PS HISTORYTRIM
set "OS_VER="
for /f "tokens=2 delims=[]" %%V in ('ver') do set "OS_VER=%%V"
set "OS_VER=!OS_VER:Version =!"
(>>"!SWX_LOGFILE!" echo() 2>nul
call :NOW
call :DLOG_WRITE INFO "Swarlex started !ADMIN_TAG! - Windows !OS_VER! - argument: [!SWX_ARG1!]"
call :DLOG_WRITE INFO "Vencord folder: !VENCORD_DIR!"
call :DLOG_WRITE INFO "Spotify folder: !SPOTIFY_DIR!"
exit /b 0

:NOW
:: Locale-independent timestamp: robocopy always prints yyyy/MM/dd HH:mm:ss. Sets NOW_DATE and NOW_TIME.
set "NOW_DATE="
for /f "tokens=1,2" %%A in ('robocopy "|" . /njh ^| findstr ":"') do if not defined NOW_DATE (
    set "NOW_DATE=%%A"
    set "NOW_TIME=%%B"
)
if not defined NOW_DATE (
    set "NOW_DATE=%date%"
    set "NOW_TIME=%time:~0,8%"
)
set "NOW_DATE=!NOW_DATE:/=-!"
exit /b 0

:DLOG
:: Writes to swarlex.log. Args: level (INFO / ACTION / WARN / ERROR), message.
call :NOW
:DLOG_WRITE
:: Same as :DLOG for callers that already ran :NOW
set "DLOG_LVL=%~1      "
set "DLOG_MSG=%~2"
(>>"!SWX_LOGFILE!" echo(!NOW_DATE! !NOW_TIME! [!DLOG_LVL:~0,6!] !DLOG_MSG!) 2>nul
exit /b 0

:LOG
:: Adds a line to the action history and swarlex.log. Args: action, result.
:: Written natively - starting PowerShell just to append one line cost ~0.3 s per action.
set "H_ACT=%~1"
set "H_RES=%~2"
call :NOW
set "H_PAD=!H_ACT!                "
if "!H_ACT:~16!"=="" (set "H_PAD=!H_PAD:~0,16!") else set "H_PAD=!H_ACT!"
(>>"!SWX_DATA!\history.log" echo(!NOW_DATE! !NOW_TIME:~0,5!  !H_PAD! !H_RES!) 2>nul
call :DLOG_WRITE ACTION "!H_ACT!: !H_RES!"
exit /b 0

:FLUSH_LOG
:: Writes the result an action left in LOG_ACTION / LOG_RESULT, once
if not defined LOG_ACTION exit /b 0
call :LOG "!LOG_ACTION!" "!LOG_RESULT!"
set "LOG_ACTION="
exit /b 0

:PROBE_PROCS
:: One process listing for everything the dashboard and the kill helpers care about (sets RUN_<name>).
:: qprocess shortens names past 12 characters (discordcanar...), so those two are matched by prefix.
for %%N in (Discord DiscordCanary DiscordPTB DiscordDevelopment Vesktop Spotify Steam) do set "RUN_%%N="
if not defined SWX_QPROC goto PROBE_PROCS_TASKLIST
for /f "tokens=*" %%L in ('qprocess 2^>nul ^| findstr /i "discord vesktop spotify steam"') do (
    for %%W in (%%L) do set "PP_IMG=%%W"
    if /i "!PP_IMG!"=="discord.exe" set "RUN_Discord=1"
    if /i "!PP_IMG!"=="discordptb.exe" set "RUN_DiscordPTB=1"
    if /i "!PP_IMG:~0,12!"=="discordcanar" set "RUN_DiscordCanary=1"
    if /i "!PP_IMG:~0,12!"=="discorddevel" set "RUN_DiscordDevelopment=1"
    if /i "!PP_IMG!"=="vesktop.exe" set "RUN_Vesktop=1"
    if /i "!PP_IMG!"=="spotify.exe" set "RUN_Spotify=1"
    if /i "!PP_IMG!"=="steam.exe" set "RUN_Steam=1"
)
exit /b 0

:PROBE_PROCS_TASKLIST
for /f "tokens=1" %%P in ('tasklist /NH 2^>nul ^| findstr /i /b /l "Discord.exe DiscordCanary.exe DiscordPTB.exe DiscordDevelopment.exe Vesktop.exe Spotify.exe steam.exe"') do set "RUN_%%~nP=1"
exit /b 0

:PROBE_DISCORD_FLAVORS
set "FLAVOR_COUNT=0"
set "FLAVOR_LIST="
for %%F in (Discord DiscordCanary DiscordPTB DiscordDevelopment) do (
    set "INST_%%F=0"
    set "PATCHED_%%F=0"
    set "LATEST_%%F="
    if exist "%LOCALAPPDATA%\%%F\" (
        rem Usually there is a single app-* folder: take it without starting "dir". Only when an update
        rem left several behind does "dir /o-d" pick the newest - the same rule PATCHER uses.
        set "APP_N=0"
        for /d %%D in ("%LOCALAPPDATA%\%%F\app-*") do if exist "%%D\resources\" (
            set /a APP_N+=1
            set "LATEST_%%F=%%~nxD"
        )
        if !APP_N! GTR 1 (
            set "LATEST_%%F="
            for /f "delims=" %%D in ('dir /b /ad /o-d "%LOCALAPPDATA%\%%F\app-*" 2^>nul') do (
                if not defined LATEST_%%F if exist "%LOCALAPPDATA%\%%F\%%D\resources\" set "LATEST_%%F=%%D"
            )
        )
        if defined LATEST_%%F (
            set "INST_%%F=1"
            set /a FLAVOR_COUNT+=1
            set "FLAVOR_LIST=!FLAVOR_LIST! %%F"
            if exist "%LOCALAPPDATA%\%%F\!LATEST_%%F!\resources\_app.asar" set "PATCHED_%%F=1"
        )
    )
)
if not defined SWX_TARGET_DISCORD set "SWX_TARGET_DISCORD=all"
set "SWX_TARGET_DISCORD=!SWX_TARGET_DISCORD: =!"
if not "!SWX_TARGET_DISCORD!"=="all" (
    set "TARGET_VALID=0"
    for %%F in (!FLAVOR_LIST!) do if /i "%%F"=="!SWX_TARGET_DISCORD!" set "TARGET_VALID=1"
    if "!TARGET_VALID!"=="0" set "SWX_TARGET_DISCORD=all"
)
if "!SWX_TARGET_DISCORD!"=="all" (
    set "TARGET_LABEL=All Clients (!FLAVOR_COUNT!)"
) else if "!SWX_TARGET_DISCORD!"=="Discord" (
    set "TARGET_LABEL=Discord [Stable]"
) else (
    set "TARGET_LABEL=!SWX_TARGET_DISCORD!"
)
exit /b 0

:KILL_DISCORD
:: Remembers whether Discord was open so RESTART_DISCORD_PROC only reopens it in that case.
:: Arg "all": close every Discord build whatever the selected target (cache clean, restore, repair).
call :PROBE_PROCS
if not defined SWX_TARGET_DISCORD set "SWX_TARGET_DISCORD=all"
set "KILL_SCOPE=!SWX_TARGET_DISCORD!"
if /i "%~1"=="all" set "KILL_SCOPE=all"
set "DISCORD_WAS_RUNNING="
if not "!KILL_SCOPE!"=="all" (
    if defined RUN_!KILL_SCOPE! set "DISCORD_WAS_RUNNING=1"
    taskkill /F /IM !KILL_SCOPE!.exe /T >nul 2>&1
) else (
    for %%N in (Discord DiscordCanary DiscordPTB DiscordDevelopment) do if defined RUN_%%N set "DISCORD_WAS_RUNNING=1"
    taskkill /F /IM Discord.exe /IM DiscordCanary.exe /IM DiscordPTB.exe /IM DiscordDevelopment.exe /T >nul 2>&1
)
set "DISCORD_KILLED=1"
if defined DISCORD_WAS_RUNNING timeout /t 2 >nul 2>&1
exit /b 0

:KILL_SPOTIFY
call :PROBE_PROCS
set "SPOTIFY_WAS_RUNNING="
if defined RUN_Spotify set "SPOTIFY_WAS_RUNNING=1"
set "SPOTIFY_KILLED=1"
taskkill /F /IM Spotify.exe /IM SpotifyUpdate.exe /IM SpotifyMigrator.exe >nul 2>&1
if defined SPOTIFY_WAS_RUNNING timeout /t 1 >nul 2>&1
exit /b 0

:: -------------------------------------------------------------
:: LIVE DASHBOARD STATUS DETECTION
:: -------------------------------------------------------------
:DETECT_STATUS
set "DISCORD_DOT=!C_GRAY!○!C_RESET!"
set "DISCORD_TXT=!C_GRAY!Offline       !C_RESET!"

set "SPOTIFY_DOT=!C_GRAY!○!C_RESET!"
set "SPOTIFY_TXT=!C_GRAY!Offline       !C_RESET!"

set "VENCORD_DOT=!C_GRAY!○!C_RESET!"
set "VENCORD_TXT=!C_GRAY!Missing       !C_RESET!"
set "VENCORD_OFF="

set "SPICETIFY_DOT=!C_GRAY!○!C_RESET!"
set "SPICETIFY_TXT=!C_GRAY!Missing       !C_RESET!"

set "UPDATE_DOT=!C_YELLOW!●!C_RESET!"
set "UPDATE_TXT=!C_YELLOW!Unprotected   !C_RESET!"

set "SP_THEME=Default"

call :PROBE_PROCS
:: Also serves the Discord menu (target switcher), so that menu no longer probes twice
call :PROBE_DISCORD_FLAVORS
set "DISCORD_PATCHED=0"
for %%F in (!FLAVOR_LIST!) do if "!PATCHED_%%F!"=="1" set "DISCORD_PATCHED=1"
if defined RUN_Discord (
    set "DISCORD_DOT=!C_GREEN!●!C_RESET!"
    set "DISCORD_TXT=!C_GREEN!Running       !C_RESET!"
) else if defined RUN_DiscordCanary (
    set "DISCORD_DOT=!C_GREEN!●!C_RESET!"
    set "DISCORD_TXT=!C_GREEN!Canary        !C_RESET!"
) else if defined RUN_DiscordPTB (
    set "DISCORD_DOT=!C_GREEN!●!C_RESET!"
    set "DISCORD_TXT=!C_GREEN!PTB           !C_RESET!"
) else if defined RUN_DiscordDevelopment (
    set "DISCORD_DOT=!C_GREEN!●!C_RESET!"
    set "DISCORD_TXT=!C_GREEN!Development   !C_RESET!"
) else if defined RUN_Vesktop (
    set "DISCORD_DOT=!C_GREEN!●!C_RESET!"
    set "DISCORD_TXT=!C_GREEN!Vesktop       !C_RESET!"
)

if defined RUN_Spotify (
    set "SPOTIFY_DOT=!C_GREEN!●!C_RESET!"
    set "SPOTIFY_TXT=!C_GREEN!Running       !C_RESET!"
)

if exist "!VENCORD_DIR!\package.json" (
    if exist "!VENCORD_DIR!\dist\patcher.js" (
        set "VENCORD_DOT=!C_CYAN!●!C_RESET!"
        set "VENCORD_TXT=!C_CYAN!Ready [Built] !C_RESET!"
    ) else (
        set "VENCORD_DOT=!C_CYAN!●!C_RESET!"
        set "VENCORD_TXT=!C_CYAN!Installed     !C_RESET!"
    )
    if "!DISCORD_PATCHED!"=="1" (
        set "VENCORD_DOT=!C_GREEN!●!C_RESET!"
        set "VENCORD_TXT=!C_GREEN!Patched       !C_RESET!"
    ) else if !FLAVOR_COUNT! GTR 0 (
        set "VENCORD_OFF=1"
        set "VENCORD_DOT=!C_YELLOW!●!C_RESET!"
        set "VENCORD_TXT=!C_YELLOW!Not Patched   !C_RESET!"
    )
)

:: Applying Spicetify unpacks Spotify's xpui.spa into an xpui folder; stock Spotify (or one that just
:: updated itself) only has the .spa. The backup entry in config-xpui.ini survives restores and updates.
set "SPICE_OFF="
if exist "!SPOTIFY_DIR!\Apps\xpui\" (
    set "SPICETIFY_DOT=!C_GREEN!●!C_RESET!"
    set "SPICETIFY_TXT=!C_GREEN!Applied       !C_RESET!"
) else (
    set "SPICE_CLI="
    if exist "%LOCALAPPDATA%\spicetify\spicetify.exe" set "SPICE_CLI=1"
    if not defined SPICE_CLI where spicetify >nul 2>&1 && set "SPICE_CLI=1"
    if defined SPICE_CLI (
        set "SPICE_OFF=1"
        set "SPICETIFY_DOT=!C_YELLOW!●!C_RESET!"
        set "SPICETIFY_TXT=!C_YELLOW!Not Applied   !C_RESET!"
    )
)
:: Read directly instead of through "type | findstr", which starts two extra processes
if exist "%APPDATA%\spicetify\config-xpui.ini" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%APPDATA%\spicetify\config-xpui.ini") do (
        for /f "tokens=1" %%K in ("%%A") do if /i "%%K"=="current_theme" for /f "tokens=*" %%V in ("%%B") do set "SP_THEME=%%V"
    )
)

if exist "%LOCALAPPDATA%\Spotify\Update" (
    pushd "%LOCALAPPDATA%\Spotify\Update" 2>nul
    if errorlevel 1 (
        set "UPDATE_DOT=!C_GREEN!●!C_RESET!"
        set "UPDATE_TXT=!C_GREEN!Protected     !C_RESET!"
    ) else (
        popd
        set "UPDATE_DOT=!C_YELLOW!●!C_RESET!"
        set "UPDATE_TXT=!C_YELLOW!Unprotected   !C_RESET!"
    )
) else (
    set "UPDATE_DOT=!C_YELLOW!●!C_RESET!"
    set "UPDATE_TXT=!C_YELLOW!Unprotected   !C_RESET!"
)
set "SP_THEME_PADDED=!SP_THEME!              "
set "SP_THEME_PADDED=!SP_THEME_PADDED:~0,14!"

set "VENCORD_UPD="
set "SPICE_UPD="
set "MILL_UPD="
set "MILL_VER="
set "SWX_UPD="
if exist "%SWX_UPDATE_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%SWX_UPDATE_FILE%") do (
        if /i "%%A"=="vencord" set "VENCORD_UPD=1"
        if /i "%%A"=="spicetify" set "SPICE_UPD=%%B"
        if /i "%%A"=="millennium" set "MILL_UPD=%%B"
        if /i "%%A"=="millver" set "MILL_VER=%%B"
        if /i "%%A"=="swarlex" set "SWX_UPD=%%B"
    )
)
if defined SWX_UPD if "!SWX_UPD!"=="!SWX_VERSION!" set "SWX_UPD="
call :DETECT_STEAM
:: A waiting update replaces the healthy value of its own row (yellow), so the dashboard never needs an
:: extra line. Problems such as "Not Patched" or "Broken" stay visible instead - they matter more.
if defined VENCORD_UPD if not defined VENCORD_OFF if exist "!VENCORD_DIR!\package.json" (
    set "VENCORD_DOT=!C_YELLOW!●!C_RESET!"
    set "VENCORD_TXT=!C_YELLOW!Update Ready  !C_RESET!"
)
if defined SPICE_UPD if not defined SPICE_OFF if exist "!SPOTIFY_DIR!\Apps\xpui\" (
    set "UPD_TMP=Update !SPICE_UPD!              "
    set "SPICETIFY_DOT=!C_YELLOW!●!C_RESET!"
    set "SPICETIFY_TXT=!C_YELLOW!!UPD_TMP:~0,14!!C_RESET!"
)
if defined MILL_UPD if "!MILL_STATE!"=="ok" (
    set "UPD_TMP=Update v!MILL_UPD!              "
    set "MILL_DOT=!C_YELLOW!●!C_RESET!"
    set "MILL_TXT=!C_YELLOW!!UPD_TMP:~0,14!!C_RESET!"
)
set "UPD_NOTE="
if defined VENCORD_UPD set "UPD_NOTE=Vencord"
if defined SPICE_UPD if defined UPD_NOTE set "UPD_NOTE=!UPD_NOTE!, "
if defined SPICE_UPD set "UPD_NOTE=!UPD_NOTE!Spicetify !SPICE_UPD!"
if defined MILL_UPD if defined UPD_NOTE set "UPD_NOTE=!UPD_NOTE!, "
if defined MILL_UPD set "UPD_NOTE=!UPD_NOTE!Millennium v!MILL_UPD!"
exit /b 0

:DETECT_STEAM
:: Millennium = wsock32.dll (the loader Steam picks up) + millennium\lib\millennium.dll. Only one of
:: them means a Steam update or a half-finished install broke it. No processes are started here.
set "STEAM_DOT=!C_GRAY!○!C_RESET!"
set "STEAM_TXT=!C_GRAY!Not Installed !C_RESET!"
if exist "!STEAM_DIR!\steam.exe" (
    set "STEAM_DOT=!C_GRAY!○!C_RESET!"
    set "STEAM_TXT=!C_GRAY!Offline       !C_RESET!"
    if defined RUN_Steam (
        set "STEAM_DOT=!C_GREEN!●!C_RESET!"
        set "STEAM_TXT=!C_GREEN!Running       !C_RESET!"
    )
)
set "MILL_STATE=missing"
set "MILL_HAS_LOADER="
set "MILL_HAS_CORE="
if exist "!STEAM_DIR!\wsock32.dll" set "MILL_HAS_LOADER=1"
if exist "!STEAM_DIR!\millennium\lib\millennium.dll" set "MILL_HAS_CORE=1"
if defined MILL_HAS_LOADER if defined MILL_HAS_CORE set "MILL_STATE=ok"
if not "!MILL_STATE!"=="ok" if defined MILL_HAS_CORE set "MILL_STATE=broken"
if not "!MILL_STATE!"=="ok" if defined MILL_HAS_LOADER if exist "!STEAM_DIR!\millennium\" set "MILL_STATE=broken"
if "!MILL_STATE!"=="ok" (
    set "MILL_DOT=!C_GREEN!●!C_RESET!"
    set "MILL_TXT=!C_GREEN!Active        !C_RESET!"
) else if "!MILL_STATE!"=="broken" (
    set "MILL_DOT=!C_RED!●!C_RESET!"
    set "MILL_TXT=!C_RED!Broken        !C_RESET!"
) else (
    set "MILL_DOT=!C_GRAY!○!C_RESET!"
    set "MILL_TXT=!C_GRAY!Missing       !C_RESET!"
)
set "MILL_PLUGINS=0"
set "MILL_THEMES=0"
for /d %%D in ("!STEAM_DIR!\millennium\plugins\*") do set /a MILL_PLUGINS+=1
for /d %%D in ("!STEAM_DIR!\millennium\themes\*") do set /a MILL_THEMES+=1
exit /b 0

:: -------------------------------------------------------------
:: ANIMATIONS (FAST NATIVE ANSI SPINNERS)
:: -------------------------------------------------------------
:PLAY_INTRO
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                        S W A R L E X                         !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!│!C_GRAY!                        Control Center                        !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
<nul set /p="!ESC![?25l"
for %%S in (⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) do (
    <nul set /p="!ESC![1G!ESC![2K!INDENT!!C_CYAN![%%S]!C_WHITE! Initializing Swarlex Control Center...!C_RESET!"
    for /l %%i in (1,1,22000) do rem
)
for %%S in (⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) do (
    <nul set /p="!ESC![1G!ESC![2K!INDENT!!C_MAGENTA![%%S]!C_WHITE! Detecting Discord ^& Spotify modules...!C_RESET!"
    for /l %%i in (1,1,22000) do rem
)
<nul set /p="!ESC![1G!ESC![2K!INDENT!!C_GREEN![●]!C_WHITE! System Ready.!C_RESET!"
echo.
<nul set /p="!ESC![?25h"
for /l %%i in (1,1,35000) do rem
exit /b 0

:SPINNER_STEP
set "S_MSG=%~1"
<nul set /p="!ESC![?25l"
for %%S in (⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) do (
    <nul set /p="!ESC![1G!ESC![2K!INDENT!!C_CYAN![%%S]!C_WHITE! !S_MSG!!C_RESET!"
    for /l %%i in (1,1,16000) do rem
)
<nul set /p="!ESC![1G!ESC![2K!INDENT!!C_GREEN![●]!C_WHITE! !S_MSG!!C_RESET!"
echo.
<nul set /p="!ESC![?25h"
exit /b 0

:NO_INPUT
:: Enter on an empty prompt just redraws the menu. 25 in a row means the input stream is closed
:: (redirected or piped input that ran out), which would otherwise redraw the menu forever.
set /a "NO_INPUT_COUNT+=1"
if !NO_INPUT_COUNT! GEQ 25 exit /b 1
exit /b 0

:CENTER_PAUSE
echo.
:: The colour code goes first: "set /p" strips leading spaces from its prompt, which lost the indent
<nul set /p="!C_GRAY!!INDENT!  Press any key to continue...!C_RESET!"
pause >nul
echo.
exit /b 0

:: -------------------------------------------------------------
:: AUTOMATIC TOOL INSTALLATION (RUNS ON USER CLICK)
:: -------------------------------------------------------------
:ENSURE_VENCORD_TOOLS
call :REFRESH_PATH
:: Git, Node.js and pnpm are looked up once per session - six "where" calls cost ~0.2 s every time
if defined VENCORD_TOOLS_OK goto ENSURE_VENCORD_SOURCE
call :SPINNER_STEP "Checking build tools [Git, Node.js, pnpm]..."

where git >nul 2>&1 || call :WINGET_INSTALL Git.Git "Git"
where node >nul 2>&1 || call :WINGET_INSTALL OpenJS.NodeJS.LTS "Node.js"

call :REFRESH_PATH
where pnpm >nul 2>&1
if errorlevel 1 (
    echo.
    echo !INDENT!!C_YELLOW![*] pnpm not found. Installing globally via npm...!C_RESET!
    call :RUN_TOOL npm install -g pnpm
    call :REFRESH_PATH
    where pnpm >nul 2>&1 || call :WINGET_INSTALL pnpm.pnpm "pnpm"
    call :REFRESH_PATH
)

set "TOOLS_OK=1"
for %%T in (git node pnpm) do (
    where %%T >nul 2>&1 || (
        echo !INDENT!!C_RED![ERROR] %%T is still not available. Install it manually and restart Swarlex.!C_RESET!
        call :DLOG ERROR "%%T is not installed and could not be installed automatically"
        set "TOOLS_OK=0"
    )
)
if "!TOOLS_OK!"=="0" exit /b 1
set "VENCORD_TOOLS_OK=1"

:ENSURE_VENCORD_SOURCE
:: Clone Vencord source if missing
if not exist "!VENCORD_DIR!\package.json" (
    echo.
    echo !INDENT!!C_CYAN![*] Vencord source repository not found. Cloning automatically...!C_RESET!
    set "VENCORD_DIR=!USER_DOCS!\Vencord"
    dir /b /a "!VENCORD_DIR!" 2>nul | findstr "^" >nul && (
        echo !INDENT!!C_RED![ERROR] The folder "!VENCORD_DIR!" exists but is not a Vencord checkout.!C_RESET!
        call :DLOG ERROR "Cannot clone Vencord: !VENCORD_DIR! exists and is not a Vencord checkout"
        exit /b 1
    )
    call :RUN_TOOL git clone --depth 1 https://github.com/Vendicated/Vencord.git "!VENCORD_DIR!"
    if errorlevel 1 (
        echo !INDENT!!C_RED![ERROR] git clone failed - check your internet connection.!C_RESET!
        call :DLOG ERROR "git clone of Vencord failed"
        exit /b 1
    )
    call :DLOG INFO "Cloned Vencord into !VENCORD_DIR!"
    if not exist "!VENCORD_DIR!\src\userplugins" mkdir "!VENCORD_DIR!\src\userplugins" 2>nul
    call :PLACE_PENDING_PLUGINS
    call :BUILD_VENCORD || exit /b 1
    echo !INDENT!!C_GREEN![+] Vencord repository setup complete.!C_RESET!
    timeout /t 2 >nul 2>&1
)
call :PLACE_PENDING_PLUGINS
exit /b 0

:PLACE_PENDING_PLUGINS
:: Userplugins from a backup restored before Vencord was set up
set "PENDING_PLUGINS=!SWX_DATA!\pending-userplugins"
if not exist "!PENDING_PLUGINS!\" exit /b 0
if not exist "!VENCORD_DIR!\src\" exit /b 0
robocopy "!PENDING_PLUGINS!" "!VENCORD_DIR!\src\userplugins" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 exit /b 0
rd /s /q "!PENDING_PLUGINS!" 2>nul
echo !INDENT!!C_GREEN![+] The userplugins from your backup are in place.!C_RESET!
call :DLOG INFO "Restore: pending userplugins placed into !VENCORD_DIR!\src\userplugins"
exit /b 0

:WINGET_INSTALL
echo.
echo !INDENT!!C_YELLOW![*] %~2 not found. Installing automatically via winget...!C_RESET!
where winget >nul 2>&1
if errorlevel 1 (
    echo !INDENT!!C_RED![ERROR] winget is not available - install %~2 manually.!C_RESET!
    call :DLOG ERROR "winget is missing - could not install %~2"
    exit /b 1
)
call :RUN_TOOL winget install --id %~1 -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
if errorlevel 1 (call :DLOG ERROR "winget could not install %~2 [%~1]") else call :DLOG INFO "Installed %~2 with winget"
call :REFRESH_PATH
exit /b 0

:ENSURE_SPOTIFY_TOOLS
call :REFRESH_PATH
:: Looked up once per session, like the Vencord tools
if defined SPICE_TOOLS_OK exit /b 0
call :SPINNER_STEP "Checking Spicetify CLI environment..."
where spicetify >nul 2>&1
if errorlevel 1 (
    echo.
    echo !INDENT!!C_YELLOW![*] Spicetify CLI not found. Installing automatically...!C_RESET!
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { iwr -useb https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | iex } catch { exit 1 }"
    call :REFRESH_PATH
    where spicetify >nul 2>&1
    if errorlevel 1 (
        echo !INDENT!!C_RED![ERROR] Spicetify installation failed - see the output above.!C_RESET!
        call :DLOG ERROR "Spicetify CLI installation failed"
        exit /b 1
    )
    call :DLOG INFO "Installed the Spicetify CLI"
    echo !INDENT!!C_GREEN![+] Spicetify installed successfully.!C_RESET!
    timeout /t 2 >nul 2>&1
)
set "SPICE_TOOLS_OK=1"
exit /b 0

:: -------------------------------------------------------------
:: 4. MAIN HUB MENU
:: -------------------------------------------------------------
:MAIN_MENU
call :CALC_CENTER
call :DETECT_STATUS
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                        S W A R L E X                         !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!│!C_GRAY!                        Control Center                        !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
echo !INDENT!  !DISCORD_DOT! Discord   : !DISCORD_TXT!   !SPOTIFY_DOT! Spotify   : !SPOTIFY_TXT!
echo !INDENT!  !VENCORD_DOT! Vencord   : !VENCORD_TXT!   !SPICETIFY_DOT! Spicetify : !SPICETIFY_TXT!
echo !INDENT!  !STEAM_DOT! Steam     : !STEAM_TXT!   !MILL_DOT! Millennium: !MILL_TXT!
echo !INDENT!  !PRIV_DOT! Privilege : !PRIV_TXT!   !UPDATE_DOT! Updates   : !UPDATE_TXT!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!1!C_WHITE!]  !C_CYAN!Discord!C_WHITE!        Patch Discord with Vencord ^& Plugins!C_RESET!
echo !INDENT!  !C_WHITE![!C_GREEN!2!C_WHITE!]  !C_GREEN!Spotify!C_WHITE!        Spicetify Mods, Updates ^& Protection!C_RESET!
echo !INDENT!  !C_WHITE![!C_BLUE!3!C_WHITE!]  !C_BLUE!Steam!C_WHITE!          Millennium Themes, Plugins ^& Updates!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!4!C_WHITE!]  !C_CYAN!App Updater!C_WHITE!    Scan ^& Upgrade Installed Apps [Winget]!C_RESET!
echo !INDENT!  !C_WHITE![!C_MAGENTA!5!C_WHITE!]  !C_MAGENTA!Backup!C_WHITE!         Full Profile Backup ^& Restore [.zip]!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_RED!6!C_WHITE!]  !C_RED!Repair!C_WHITE!         Scan ^& Fix Common Problems [1-Click]!C_RESET!
if defined SWX_UPD (
    echo !INDENT!  !C_WHITE![!C_YELLOW!7!C_WHITE!]  !C_YELLOW!Settings!C_WHITE!       !C_YELLOW!● Swarlex v!SWX_UPD! Is Ready To Install!C_RESET!
) else (
    echo !INDENT!  !C_WHITE![!C_YELLOW!7!C_WHITE!]  !C_YELLOW!Settings!C_WHITE!       Preferences, Admin Mode ^& Logs!C_RESET!
)
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Exit!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "MAIN_CHOICE="
set /p "MAIN_CHOICE=!PROMPT_INDENT!!C_CYAN!›!C_WHITE! Select an option [0-7]: !C_RESET!"
if not defined MAIN_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MAIN_MENU
)
set "NO_INPUT_COUNT=0"
set "MAIN_CHOICE=!MAIN_CHOICE: =!"
if "!MAIN_CHOICE!"=="1" goto ROUTE_VENCORD
if "!MAIN_CHOICE!"=="2" goto ROUTE_SPICETIFY
if "!MAIN_CHOICE!"=="3" goto MENU_STEAM
if "!MAIN_CHOICE!"=="4" goto ROUTE_APP_UPDATER
if "!MAIN_CHOICE!"=="5" goto MENU_BACKUP
if "!MAIN_CHOICE!"=="6" goto ACTION_REPAIR
if "!MAIN_CHOICE!"=="7" goto MENU_SETTINGS
if "!MAIN_CHOICE!"=="0" goto EXIT_SCRIPT
if /i "!MAIN_CHOICE!"=="q" goto EXIT_SCRIPT
if /i "!MAIN_CHOICE!"=="exit" goto EXIT_SCRIPT

goto MAIN_MENU


:: -------------------------------------------------------------
:: 4B. APPLICATION UPDATER (WINGET)
:: -------------------------------------------------------------
:ROUTE_APP_UPDATER
call :CALC_CENTER
where winget >nul 2>&1
if errorlevel 1 (
    cls
    echo.
    echo.
    echo !INDENT!!C_RED!╭──────────────────────────────────────────────────────────────╮!C_RESET!
    echo !INDENT!!C_RED!│!C_WHITE!                     WINGET NOT FOUND                         !C_RED!│!C_RESET!
    echo !INDENT!!C_RED!╰──────────────────────────────────────────────────────────────╯!C_RESET!
    echo.
    echo !INDENT!  !C_RED![^^!] Windows Package Manager [winget] is not installed.!C_RESET!
    echo !INDENT!  !C_GRAY!Install "App Installer" from the Microsoft Store first.!C_RESET!
    echo.
    call :CENTER_PAUSE
    goto MAIN_MENU
)
cls
echo.
echo.
call :SPINNER_STEP "Checking for available application updates via Winget..."
call :RUN_PS WINGET_UPDATER
if "!errorlevel!"=="42" goto SWX_QUIT
goto MAIN_MENU


:: -------------------------------------------------------------
:: 5. DISCORD / VENCORD MENU
:: -------------------------------------------------------------
:ROUTE_VENCORD
call :CALC_CENTER
cls
echo.
echo.
call :ENSURE_VENCORD_TOOLS
if errorlevel 1 (
    call :CENTER_PAUSE
    goto MAIN_MENU
)

:MENU_VENCORD
call :CALC_CENTER
call :DETECT_STATUS
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                  DISCORD ^& VENCORD CONTROLS                  !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
echo !INDENT!  !DISCORD_DOT! Discord   : !DISCORD_TXT!   !VENCORD_DOT! Vencord   : !VENCORD_TXT!
if !FLAVOR_COUNT! GTR 1 (
    set "TL_DISP=!TARGET_LABEL!                "
    set "TL_DISP=!TL_DISP:~0,16!"
    echo !INDENT!  !C_WHITE!●!C_RESET! Target    : !C_CYAN!!TL_DISP!!C_RESET!  !C_CYAN!●!C_RESET! Switch    : !C_WHITE![!C_CYAN!T!C_WHITE!] !C_GRAY!Next Client!C_RESET!
)
if defined VENCORD_UPD echo !INDENT!  !C_YELLOW!● A Vencord update is available - use [2] Update Vencord!C_RESET!
if defined VENCORD_OFF echo !INDENT!  !C_YELLOW!● Vencord is not patched into Discord - use [1] Patch Discord!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GREEN!1!C_WHITE!]  !C_GREEN!Patch Discord!C_WHITE!       Build ^& Inject Vencord Bundle!C_RESET!
echo !INDENT!  !C_WHITE![!C_MAGENTA!2!C_WHITE!]  !C_MAGENTA!Update Vencord!C_WHITE!      Git Pull Latest Release ^& Re-inject!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_YELLOW!3!C_WHITE!]  !C_YELLOW!Plugin Hub!C_WHITE!          Download ^& Manage Custom Plugins!C_RESET!
echo !INDENT!  !C_WHITE![!C_YELLOW!4!C_WHITE!]  !C_YELLOW!QuickCSS!C_WHITE!            Edit Custom Discord Stylesheet!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!5!C_WHITE!]  !C_CYAN!Clean Cache!C_WHITE!         Clear Discord Cache - Login Is Kept!C_RESET!
echo !INDENT!  !C_WHITE![!C_RED!6!C_WHITE!]  !C_RED!Uninject!C_WHITE!            Restore Discord to Default State!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back!C_WHITE!                Return to Main Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "V_CHOICE="
set /p "V_CHOICE=!PROMPT_INDENT!!C_CYAN!›!C_WHITE! Select an action [0-6]: !C_RESET!"
if not defined V_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_VENCORD
)
set "NO_INPUT_COUNT=0"
set "V_CHOICE=!V_CHOICE: =!"
if /i "!V_CHOICE!"=="t" goto ACTION_CYCLE_DISCORD_TARGET
if "!V_CHOICE!"=="1" goto ACTION_BUILD_AND_INJECT
if "!V_CHOICE!"=="2" goto ACTION_UPDATE
if "!V_CHOICE!"=="3" goto MENU_USERPLUGINS
if "!V_CHOICE!"=="4" goto ACTION_EDIT_QUICKCSS
if "!V_CHOICE!"=="5" goto ACTION_DISCORD_CLEAN_CACHE
if "!V_CHOICE!"=="6" goto ACTION_UNINJECT
if "!V_CHOICE!"=="0" goto MAIN_MENU
if /i "!V_CHOICE!"=="b" goto MAIN_MENU

goto MENU_VENCORD

:ACTION_CYCLE_DISCORD_TARGET
call :PROBE_DISCORD_FLAVORS
if !FLAVOR_COUNT! LEQ 1 goto MENU_VENCORD
set "NEXT_TARGET="
set "FOUND_CUR="
for %%F in (!FLAVOR_LIST!) do (
    if defined FOUND_CUR (
        if not defined NEXT_TARGET set "NEXT_TARGET=%%F"
    )
    if /i "%%F"=="!SWX_TARGET_DISCORD!" set "FOUND_CUR=1"
)
if "!SWX_TARGET_DISCORD!"=="all" (
    for %%F in (!FLAVOR_LIST!) do if not defined NEXT_TARGET set "NEXT_TARGET=%%F"
) else if not defined NEXT_TARGET (
    set "NEXT_TARGET=all"
)
set "SWX_TARGET_DISCORD=!NEXT_TARGET!"
goto MENU_VENCORD

:: -------------------------------------------------------------
:: 6. SPOTIFY / SPICETIFY MENU
:: -------------------------------------------------------------
:ROUTE_SPICETIFY
call :CALC_CENTER
cls
echo.
echo.
call :ENSURE_SPOTIFY_TOOLS
if errorlevel 1 (
    call :CENTER_PAUSE
    goto MAIN_MENU
)

:MENU_SPICETIFY
call :CALC_CENTER
call :DETECT_STATUS
cls
echo.
echo.
echo !INDENT!!C_GREEN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_GREEN!│!C_WHITE!                 SPOTIFY ^& SPICETIFY CONTROLS                 !C_GREEN!│!C_RESET!
echo !INDENT!!C_GREEN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
echo !INDENT!  !SPOTIFY_DOT! Spotify   : !SPOTIFY_TXT!   !SPICETIFY_DOT! Spicetify : !SPICETIFY_TXT!
echo !INDENT!  !C_WHITE!●!C_WHITE! Theme     : !C_CYAN!!SP_THEME_PADDED!!C_WHITE!   !UPDATE_DOT! Updates   : !UPDATE_TXT!
if defined SPICE_UPD echo !INDENT!  !C_YELLOW!● Spicetify !SPICE_UPD! is available - use [2] Update Spicetify!C_RESET!
if defined SPICE_OFF echo !INDENT!  !C_YELLOW!● Spicetify is not applied - use [1] Apply Spicetify!C_RESET!
if "!IS_STORE_SPOTIFY!"=="1" echo !INDENT!  !C_RED![^^!] Notice: Microsoft Store Spotify detected.!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GREEN!1!C_WHITE!]  !C_GREEN!Apply Spicetify!C_WHITE!     Inject Modifications into Spotify!C_RESET!
echo !INDENT!  !C_WHITE![!C_MAGENTA!2!C_WHITE!]  !C_MAGENTA!Update Spicetify!C_WHITE!    Update Spicetify CLI ^& Re-apply!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_YELLOW!3!C_WHITE!]  !C_YELLOW!Update Guard!C_WHITE!        Block / Unblock Automatic Updates!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!4!C_WHITE!]  !C_CYAN!Clean Cache!C_WHITE!         Clear Streaming ^& Image Cache!C_RESET!
echo !INDENT!  !C_WHITE![!C_RED!5!C_WHITE!]  !C_RED!Restore Spotify!C_WHITE!     Reset Spotify to Clean Vanilla State!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back!C_WHITE!                Return to Main Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "S_CHOICE="
set /p "S_CHOICE=!PROMPT_INDENT!!C_GREEN!›!C_WHITE! Select an action [0-5]: !C_RESET!"
if not defined S_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_SPICETIFY
)
set "NO_INPUT_COUNT=0"
set "S_CHOICE=!S_CHOICE: =!"
if "!S_CHOICE!"=="1" goto ACTION_SPICETIFY_APPLY
if "!S_CHOICE!"=="2" goto ACTION_SPICETIFY_UPDATE
if "!S_CHOICE!"=="3" goto ACTION_SPICETIFY_TOGGLE_UPDATES
if "!S_CHOICE!"=="4" goto ACTION_SPICETIFY_CLEAN_CACHE
if "!S_CHOICE!"=="5" goto ACTION_SPICETIFY_RESTORE
if "!S_CHOICE!"=="0" goto MAIN_MENU
if /i "!S_CHOICE!"=="b" goto MAIN_MENU

goto MENU_SPICETIFY

:: -------------------------------------------------------------
:: DISCORD / VENCORD ACTIONS
:: -------------------------------------------------------------
:BUILD_VENCORD
cd /d "!VENCORD_DIR!" 2>nul
if errorlevel 1 (
    echo !INDENT!!C_RED![ERROR] Vencord folder not found: !VENCORD_DIR!!C_RESET!
    exit /b 1
)
:: A plugin check that was interrupted leaves plugins parked here - put them back first
if exist "src\userplugins\.swarlex-testing\" (
    set "SWX_DOCTOR_MODE=recover"
    call :RUN_PS DOCTOR
)
call :SPINNER_STEP "Verifying dependencies..."
if not exist "node_modules\" (
    call :RUN_TOOL pnpm install --config.confirmModulesPurge=false
) else (
    call pnpm install --prefer-offline --config.confirmModulesPurge=false >nul 2>&1
)
call :SPINNER_STEP "Building Vencord bundle..."
:: esbuild writes its bundles in parallel and the console output interleaves, so it goes to a log instead
call node --require=./scripts/suppressExperimentalWarnings.js scripts/build/build.mjs > "!SWX_BUILD_LOG!" 2>&1
if not errorlevel 1 exit /b 0
echo !INDENT!!C_YELLOW![*] Build failed - reinstalling dependencies and retrying...!C_RESET!
call pnpm install --config.confirmModulesPurge=false > "!SWX_INSTALL_LOG!" 2>&1
if errorlevel 1 (
    echo !INDENT!!C_RED![ERROR] Installing dependencies failed:!C_RESET!
    set "SWX_LOG=!SWX_INSTALL_LOG!"
    call :RUN_PS BUILDLOG
    exit /b 1
)
call :SPINNER_STEP "Rebuilding Vencord bundle..."
call node --require=./scripts/suppressExperimentalWarnings.js scripts/build/build.mjs > "!SWX_BUILD_LOG!" 2>&1
if not errorlevel 1 exit /b 0
if exist "src\userplugins\" (
    set "SWX_DOCTOR_MODE=diagnose"
    call :RUN_PS DOCTOR
    if not errorlevel 1 exit /b 0
)
echo !INDENT!!C_RED![ERROR] Vencord build failed:!C_RESET!
set "SWX_LOG=!SWX_BUILD_LOG!"
call :RUN_PS BUILDLOG
exit /b 1

:PATCH_DISCORD
:: Arg: install or uninstall. The official VencordInstallerCli silently skips patching
:: for source [dev] builds while still reporting success, so the patch is applied here.
set "SWX_MODE=%~1"
call :RUN_PS PATCHER
exit /b !errorlevel!

:ACTION_BUILD_AND_INJECT
echo.
set "RC=1"
set "LOG_ACTION=Patch Discord"
set "LOG_RESULT=failed"
if not exist "!VENCORD_DIR!\package.json" (
    call :ENSURE_VENCORD_TOOLS
    if errorlevel 1 goto FINISH_VENCORD
)
call :PROBE_DISCORD_FLAVORS
echo !INDENT!  !C_CYAN![*] Target: !TARGET_LABEL!!C_RESET!
call :BUILD_VENCORD
if errorlevel 1 (
    set "LOG_RESULT=failed - build error"
    goto FINISH_VENCORD
)
echo !INDENT!!C_GREEN![+] Build successful.!C_RESET!
call :SPINNER_STEP "Closing Discord processes and injecting patch..."
call :KILL_DISCORD
call :PATCH_DISCORD install
if errorlevel 1 (
    set "LOG_RESULT=failed - could not patch Discord"
    echo.
    echo !INDENT!!C_RED![ERROR] Injection failed - Discord was NOT patched.!C_RESET!
    echo !INDENT!!C_GRAY!    Make sure Discord is fully closed, then try again.!C_RESET!
    call :RESTART_DISCORD_PROC
    goto FINISH_VENCORD
)
set "RC=0"
set "LOG_RESULT=patched"
echo !INDENT!!C_GREEN![+] Vencord successfully patched into !TARGET_LABEL!.!C_RESET!
call :RESTART_DISCORD_PROC
goto FINISH_VENCORD

:ACTION_UPDATE
echo.
set "RC=1"
set "LOG_ACTION=Update Vencord"
set "LOG_RESULT=failed"
if not exist "!VENCORD_DIR!\package.json" (
    call :ENSURE_VENCORD_TOOLS
    if errorlevel 1 goto FINISH_VENCORD
)
call :SPINNER_STEP "Updating Vencord [download, build, inject]..."
cd /d "!VENCORD_DIR!" 2>nul
if errorlevel 1 (
    echo !INDENT!!C_RED![ERROR] Vencord folder not found: !VENCORD_DIR!!C_RESET!
    goto FINISH_VENCORD
)
:: Close Discord first: Vencord's built-in updater runs "git fetch" in this folder on startup, and two
:: fetches at once leave FETCH_HEAD with duplicate entries that make "git pull" fail
call :KILL_DISCORD
call :SNAPSHOT vencord
set "STASHED=0"
git diff --quiet HEAD >nul 2>&1
if errorlevel 1 (
    git stash push -m "swarlex-auto-update" >nul 2>&1
    if not errorlevel 1 set "STASHED=1"
)
set "OLD_HEAD="
for /f %%H in ('git rev-parse --short HEAD 2^>nul') do set "OLD_HEAD=%%H"
:: Merging the upstream ref instead of FETCH_HEAD keeps a stray parallel fetch from breaking the update
call :RUN_TOOL git fetch -q origin
set "PULL_ERR=!errorlevel!"
if "!PULL_ERR!"=="0" (
    call :RUN_TOOL git merge -q --ff-only @{u}
    set "PULL_ERR=!errorlevel!"
)
if "!STASHED!"=="1" (
    git stash pop >nul 2>&1
    if errorlevel 1 echo !INDENT!!C_YELLOW![*] Your local source edits conflicted with the update - they are kept in "git stash".!C_RESET!
)
if not "!PULL_ERR!"=="0" (
    set "LOG_RESULT=failed - could not download the update"
    echo.
    echo !INDENT!!C_RED![ERROR] Could not update the Vencord source - see the git message above.!C_RESET!
    call :RESTART_DISCORD_PROC
    goto FINISH_VENCORD
)
set "NEW_HEAD="
for /f %%H in ('git rev-parse --short HEAD 2^>nul') do set "NEW_HEAD=%%H"
if "!OLD_HEAD!"=="!NEW_HEAD!" (
    set "UPD_DESC=already up to date [!NEW_HEAD!]"
    echo !INDENT!!C_GREEN![+] Vencord source is already up to date [!NEW_HEAD!].!C_RESET!
) else (
    set "UPD_DESC=!OLD_HEAD! -> !NEW_HEAD!"
    echo !INDENT!!C_GREEN![+] Vencord source updated: !OLD_HEAD! -^> !NEW_HEAD!!C_RESET!
)
call :START_UPDATE_CHECK fresh
call :BUILD_VENCORD
if errorlevel 1 (
    set "LOG_RESULT=failed - build error [!UPD_DESC!]"
    call :RESTART_DISCORD_PROC
    goto FINISH_VENCORD
)
call :PATCH_DISCORD install
if errorlevel 1 (
    set "LOG_RESULT=failed - could not patch Discord [!UPD_DESC!]"
    echo.
    echo !INDENT!!C_RED![ERROR] Injection failed - Discord was NOT patched.!C_RESET!
    call :RESTART_DISCORD_PROC
    goto FINISH_VENCORD
)
set "RC=0"
set "LOG_RESULT=!UPD_DESC!, patched"
echo !INDENT!!C_GREEN![+] Vencord updated to latest release and injected.!C_RESET!
call :RESTART_DISCORD_PROC
goto FINISH_VENCORD

:ACTION_UNINJECT
echo.
set "RC=1"
set "LOG_ACTION=Uninject"
set "LOG_RESULT=failed"
call :PROBE_DISCORD_FLAVORS
echo !INDENT!  !C_CYAN![*] Target: !TARGET_LABEL!!C_RESET!
call :SPINNER_STEP "Removing Vencord patch from !TARGET_LABEL!..."
call :KILL_DISCORD
call :PATCH_DISCORD uninstall
if errorlevel 1 (
    echo !INDENT!!C_RED![ERROR] Could not fully restore Discord - close it and try again.!C_RESET!
    call :RESTART_DISCORD_PROC
) else (
    set "RC=0"
    set "LOG_RESULT=Vencord removed from !TARGET_LABEL!"
    echo !INDENT!!C_GREEN![+] Vencord uninstalled from !TARGET_LABEL!.!C_RESET!
    call :RESTART_DISCORD_PROC
)
goto FINISH_VENCORD

:FINISH_VENCORD
call :FLUSH_LOG
if defined CLI_MODE exit /b !RC!
call :CENTER_PAUSE
goto MENU_VENCORD

:ACTION_DISCORD_CLEAN_CACHE
echo.
echo !INDENT!!C_CYAN![i] Clears Discord's cache. Your login, messages and settings are kept.!C_RESET!
set "CONFIRM_DCACHE="
set /p "CONFIRM_DCACHE=!PROMPT_INDENT!Clean Discord cache? [Y/N]: "
if /i "!CONFIRM_DCACHE!"=="yes" set "CONFIRM_DCACHE=y"
if /i not "!CONFIRM_DCACHE!"=="y" goto MENU_VENCORD
call :SPINNER_STEP "Cleaning Discord cache..."
:: DISCACHE cleans every Discord build, so all of them have to be closed
call :KILL_DISCORD all
call :RUN_PS DISCACHE
call :RESTART_DISCORD_PROC
call :CENTER_PAUSE
goto MENU_VENCORD

:ACTION_EDIT_QUICKCSS
echo.
call :SPINNER_STEP "Opening Discord QuickCSS stylesheet..."
if not exist "%APPDATA%\Vencord\settings" mkdir "%APPDATA%\Vencord\settings" 2>nul
if not exist "%APPDATA%\Vencord\settings\quickCss.css" type nul > "%APPDATA%\Vencord\settings\quickCss.css"
where code.cmd >nul 2>&1
if !errorlevel! equ 0 (
    rem "start" would run code.cmd through "cmd /k" and leave an empty console window behind
    call code "%APPDATA%\Vencord\settings\quickCss.css"
) else (
    start "" notepad.exe "%APPDATA%\Vencord\settings\quickCss.css"
)
goto MENU_VENCORD

:RESTART_DISCORD_PROC
:: Only after KILL_DISCORD closed it in this action, then per the "Reopen Apps" setting:
:: ifopen = only if it was open before, always, never
if not defined DISCORD_KILLED exit /b 0
set "DISCORD_KILLED="
if /i "!CFG_RELAUNCH!"=="never" exit /b 0
if /i not "!CFG_RELAUNCH!"=="always" if not defined DISCORD_WAS_RUNNING exit /b 0
call :SPINNER_STEP "Relaunching Discord client..."
if defined KILL_SCOPE if not "!KILL_SCOPE!"=="all" (
    call :START_DISCORD !KILL_SCOPE! && exit /b 0
)
set "RESTARTED="
for %%F in (Discord DiscordCanary DiscordPTB DiscordDevelopment) do (
    if defined RUN_%%F call :START_DISCORD %%F && set "RESTARTED=1"
)
if not defined RESTARTED if /i "!CFG_RELAUNCH!"=="always" (
    call :START_DISCORD Discord || call :START_DISCORD DiscordCanary
)
exit /b 0

:START_DISCORD
:: Arg: Discord build. Returns 1 if it is not installed. From an elevated Swarlex, Discord is started
:: through explorer.exe so it runs with normal rights - an elevated Discord breaks drag and drop and
:: lets Vencord's updater create files in the Vencord folder that later need admin rights to change.
set "SD_F=%~1"
if not exist "%LOCALAPPDATA%\!SD_F!\Update.exe" exit /b 1
if "!IS_ADMIN!"=="1" (
    set "SD_APP="
    for /f "delims=" %%D in ('dir /b /ad /o-d "%LOCALAPPDATA%\!SD_F!\app-*" 2^>nul') do if not defined SD_APP set "SD_APP=%%D"
    if defined SD_APP if exist "%LOCALAPPDATA%\!SD_F!\!SD_APP!\!SD_F!.exe" (
        start "" explorer.exe "%LOCALAPPDATA%\!SD_F!\!SD_APP!\!SD_F!.exe"
        exit /b 0
    )
)
start "" "%LOCALAPPDATA%\!SD_F!\Update.exe" --processStart !SD_F!.exe
exit /b 0

:: -------------------------------------------------------------
:: VENCORD PLUGIN HUB
:: -------------------------------------------------------------
:MENU_USERPLUGINS
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                      VENCORD PLUGIN HUB                      !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
echo !INDENT!  !C_GRAY!Path: !VENCORD_DIR!\src\userplugins!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GREEN!1!C_WHITE!]  !C_GREEN!Install Plugin!C_WHITE!      From a GitHub Repo, Folder or File!C_RESET!
echo !INDENT!  !C_WHITE![!C_MAGENTA!2!C_WHITE!]  !C_MAGENTA!Manage Plugins!C_WHITE!      Turn Plugins On / Off or Delete Them!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_YELLOW!3!C_WHITE!]  !C_YELLOW!Open Folder!C_WHITE!         Open userplugins in Explorer!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back!C_WHITE!                Return to Discord Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "UP_CHOICE="
set /p "UP_CHOICE=!PROMPT_INDENT!!C_CYAN!›!C_WHITE! Select an action [0-3]: !C_RESET!"
if not defined UP_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_USERPLUGINS
)
set "NO_INPUT_COUNT=0"
set "UP_CHOICE=!UP_CHOICE: =!"
if "!UP_CHOICE!"=="1" goto ACTION_INSTALL_PLUGIN
if "!UP_CHOICE!"=="2" goto ACTION_MANAGE_PLUGINS
if "!UP_CHOICE!"=="3" goto ACTION_PLUGINS_FOLDER
if "!UP_CHOICE!"=="0" goto MENU_VENCORD
if /i "!UP_CHOICE!"=="b" goto MENU_VENCORD
goto MENU_USERPLUGINS

:ACTION_PLUGINS_FOLDER
if not exist "!VENCORD_DIR!\src\userplugins" mkdir "!VENCORD_DIR!\src\userplugins" 2>nul
start "" explorer.exe "!VENCORD_DIR!\src\userplugins"
goto MENU_USERPLUGINS

:ACTION_INSTALL_PLUGIN
echo.
echo !INDENT!  !C_CYAN!Paste the GitHub link of the plugin:!C_RESET!
echo !INDENT!  !C_GRAY!Repo    https://github.com/user/plugin-name!C_RESET!
echo !INDENT!  !C_GRAY!Folder  https://github.com/user/repo/tree/main/pluginName!C_RESET!
echo !INDENT!  !C_GRAY!File    https://github.com/user/repo/blob/main/plugin.tsx!C_RESET!
echo.
set "SWX_PLUGIN_URL="
set /p "SWX_PLUGIN_URL=!PROMPT_INDENT!Link: "
if not defined SWX_PLUGIN_URL goto MENU_USERPLUGINS
set "SWX_PLUGIN_URL=!SWX_PLUGIN_URL:"=!"
if not defined SWX_PLUGIN_URL goto MENU_USERPLUGINS
echo.
call :RUN_PS PLUGININSTALL
call :CENTER_PAUSE
goto MENU_USERPLUGINS

:ACTION_MANAGE_PLUGINS
call :RUN_PS MANAGE
goto MENU_USERPLUGINS

:: -------------------------------------------------------------
:: SPOTIFY / SPICETIFY ACTIONS
:: -------------------------------------------------------------
:ACTION_SPICETIFY_APPLY
echo.
set "RC=1"
set "LOG_ACTION=Apply Spicetify"
set "LOG_RESULT=failed"
call :ENSURE_SPOTIFY_TOOLS
if errorlevel 1 goto FINISH_SPICETIFY
call :SPINNER_STEP "Closing Spotify client..."
call :KILL_SPOTIFY
call :SPINNER_STEP "Applying Spicetify patch to Spotify..."
call :SPICETIFY apply !SPICETIFY_FLAGS!
if errorlevel 1 call :SPICETIFY backup apply !SPICETIFY_FLAGS!
if errorlevel 1 (
    echo.
    echo !INDENT!  !C_RED![ERROR] Spicetify could not be applied - close Spotify first.!C_RESET!
    call :RESTART_SPOTIFY_PROC
) else (
    set "RC=0"
    set "LOG_RESULT=applied"
    echo !INDENT!  !C_GREEN![+] Spicetify applied successfully.!C_RESET!
    rem spicetify apply restarts Spotify on its own, so this runs regardless of the Reopen Apps setting
    set "SPOTIFY_KILLED="
    call :SPINNER_STEP "Relaunching Spotify..."
    call :START_SPOTIFY_PROC
)
goto FINISH_SPICETIFY

:ACTION_SPICETIFY_UPDATE
echo.
set "RC=1"
call :ENSURE_SPOTIFY_TOOLS
if errorlevel 1 goto FINISH_SPICETIFY
call :SNAPSHOT spicetify
call :SPINNER_STEP "Checking for Spicetify updates..."
call :RUN_PS SPICEUPDATE
set "UPD_RC=!errorlevel!"
if "!UPD_RC!"=="0" set "RC=0"
if "!UPD_RC!"=="10" set "RC=0"
if "!RC!"=="0" call :START_UPDATE_CHECK fresh
goto FINISH_SPICETIFY

:ACTION_SPICETIFY_RESTORE
echo.
echo !INDENT!  !C_YELLOW![^^!] Restoring Spotify to original unmodded state...!C_RESET!
set "CONFIRM_RESTORE="
set /p "CONFIRM_RESTORE=!PROMPT_INDENT!Are you sure you want to reset Spotify? [Y/N]: "
if /i "!CONFIRM_RESTORE!"=="yes" set "CONFIRM_RESTORE=y"
if /i not "!CONFIRM_RESTORE!"=="y" goto MENU_SPICETIFY
call :SPINNER_STEP "Restoring Spotify vanilla files..."
call :KILL_SPOTIFY
call :SPICETIFY restore !SPICETIFY_FLAGS!
if errorlevel 1 (
    echo !INDENT!  !C_RED![ERROR] Spicetify restore failed - see the output above.!C_RESET!
    call :LOG "Restore Spotify" "failed"
) else (
    echo !INDENT!  !C_GREEN![+] Spotify restored to default clean state.!C_RESET!
    call :LOG "Restore Spotify" "Spicetify removed from Spotify"
)
call :RESTART_SPOTIFY_PROC
call :CENTER_PAUSE
goto MENU_SPICETIFY

:FINISH_SPICETIFY
call :FLUSH_LOG
if defined CLI_MODE exit /b !RC!
call :CENTER_PAUSE
goto MENU_SPICETIFY

:ACTION_SPICETIFY_TOGGLE_UPDATES
call :CALC_CENTER
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!       SPOTIFY AUTOMATIC UPDATE BLOCKER [PROTECT MODS]        !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
set "UPD_DIR=%LOCALAPPDATA%\Spotify\Update"
set "IS_LOCKED=0"
set "SPOTIFY_KILLED="
set "NEED_ADMIN="
if exist "!UPD_DIR!" (
    pushd "!UPD_DIR!" 2>nul
    if errorlevel 1 (
        set "IS_LOCKED=1"
    ) else (
        popd
        set "IS_LOCKED=0"
    )
)

if "!IS_LOCKED!"=="1" goto TOGGLE_IS_LOCKED

:TOGGLE_IS_UNLOCKED
echo !INDENT!  !C_YELLOW![*] Spotify auto-updates are UNLOCKED [may break mods].!C_RESET!
echo !INDENT!  !C_CYAN!Do you want to lock updates to protect Spicetify? [Y/N]!C_RESET!
echo.
set "TOGGLE_CHOICE="
set /p "TOGGLE_CHOICE=!PROMPT_INDENT!Enter choice [Y]: "
if /i "!TOGGLE_CHOICE!"=="no" set "TOGGLE_CHOICE=n"
if /i not "!TOGGLE_CHOICE!"=="n" call :DO_LOCK_UPDATES
goto TOGGLE_DONE

:TOGGLE_IS_LOCKED
echo !INDENT!  !C_GREEN![*] Spotify auto-updates are currently LOCKED [Safe Mode].!C_RESET!
echo !INDENT!  !C_YELLOW!Do you want to unlock and permit official updates? [Y/N]!C_RESET!
echo.
set "TOGGLE_CHOICE="
set /p "TOGGLE_CHOICE=!PROMPT_INDENT!Enter choice [N]: "
if /i "!TOGGLE_CHOICE!"=="yes" set "TOGGLE_CHOICE=y"
if /i "!TOGGLE_CHOICE!"=="y" call :DO_UNLOCK_UPDATES

:TOGGLE_DONE
call :RESTART_SPOTIFY_PROC
if defined NEED_ADMIN if "!IS_ADMIN!"=="0" (
    call :OFFER_ELEVATE spicetify
    if not errorlevel 1 goto SWX_QUIT
)
call :CENTER_PAUSE
goto MENU_SPICETIFY

:DO_UNLOCK_UPDATES
call :SPINNER_STEP "Removing update lock..."
icacls "%UPD_DIR%" /remove:d "%USERNAME%" >nul 2>&1
attrib -r -s -h "%UPD_DIR%" >nul 2>&1
del /f /q "%UPD_DIR%" 2>nul
mkdir "%UPD_DIR%" 2>nul
if exist "%UPD_DIR%\" (
    echo !INDENT!  !C_GREEN![+] Spotify update lock REMOVED.!C_RESET!
    call :LOG "Update Guard" "Spotify updates unlocked"
) else (
    echo !INDENT!  !C_RED![ERROR] Could not remove the update lock - admin rights needed.!C_RESET!
    call :DLOG ERROR "Update Guard: could not remove the Spotify update lock [admin=!IS_ADMIN!]"
    set "NEED_ADMIN=1"
)
exit /b 0

:DO_LOCK_UPDATES
call :SPINNER_STEP "Enforcing update guard..."
if not exist "%LOCALAPPDATA%\Spotify\" (
    echo !INDENT!  !C_RED![ERROR] No Spotify data folder - start Spotify once first.!C_RESET!
    exit /b 1
)
call :KILL_SPOTIFY
if exist "%UPD_DIR%" (
    icacls "%UPD_DIR%" /reset /T >nul 2>&1
    attrib -r -s -h "%UPD_DIR%" >nul 2>&1
    rd /s /q "%UPD_DIR%" 2>nul
    del /f /q "%UPD_DIR%" 2>nul
)
type nul > "%UPD_DIR%" 2>nul
if not exist "%UPD_DIR%" (
    echo !INDENT!  !C_RED![ERROR] Could not create the update lock - admin rights needed.!C_RESET!
    call :DLOG ERROR "Update Guard: could not create the Spotify update lock [admin=!IS_ADMIN!]"
    set "NEED_ADMIN=1"
    exit /b 1
)
if exist "%UPD_DIR%\" (
    echo !INDENT!  !C_RED![ERROR] The Update folder is in use - close Spotify first.!C_RESET!
    call :DLOG ERROR "Update Guard: the Spotify Update folder is in use"
    exit /b 1
)
attrib +r +s +h "%UPD_DIR%" >nul 2>&1
icacls "%UPD_DIR%" /deny "%USERNAME%:(W,D)" >nul 2>&1
echo !INDENT!  !C_GREEN![+] Spotify auto-updates LOCKED successfully.!C_RESET!
call :LOG "Update Guard" "Spotify updates locked"
exit /b 0

:ACTION_SPICETIFY_CLEAN_CACHE
echo.
echo !INDENT!  !C_CYAN![i] Clears Spotify's cache. Downloaded songs are kept.!C_RESET!
set "CONFIRM_CACHE="
set /p "CONFIRM_CACHE=!PROMPT_INDENT!Clean Spotify cache? [Y/N]: "
if /i "!CONFIRM_CACHE!"=="yes" set "CONFIRM_CACHE=y"
if /i not "!CONFIRM_CACHE!"=="y" goto MENU_SPICETIFY

call :SPINNER_STEP "Cleaning cache files..."
call :KILL_SPOTIFY
call :RUN_PS SPOTCACHE
call :RESTART_SPOTIFY_PROC
call :CENTER_PAUSE
goto MENU_SPICETIFY

:RESTART_SPOTIFY_PROC
:: Same rules as RESTART_DISCORD_PROC
if not defined SPOTIFY_KILLED exit /b 0
set "SPOTIFY_KILLED="
if /i "!CFG_RELAUNCH!"=="never" exit /b 0
if /i not "!CFG_RELAUNCH!"=="always" if not defined SPOTIFY_WAS_RUNNING exit /b 0
call :SPINNER_STEP "Relaunching Spotify..."
call :START_SPOTIFY_PROC
exit /b 0

:START_SPOTIFY_PROC
:: explorer.exe starts it with normal rights when Swarlex itself runs as Administrator
if exist "%APPDATA%\Spotify\Spotify.exe" (
    if "!IS_ADMIN!"=="1" (
        start "" explorer.exe "%APPDATA%\Spotify\Spotify.exe"
    ) else (
        start "" "%APPDATA%\Spotify\Spotify.exe"
    )
) else if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\Spotify.exe" (
    start "" "%LOCALAPPDATA%\Microsoft\WindowsApps\Spotify.exe"
) else (
    start "" spotify:
)
exit /b 0

:: -------------------------------------------------------------
:: STEAM / MILLENNIUM
:: -------------------------------------------------------------
:MENU_STEAM
call :CALC_CENTER
call :DETECT_STATUS
cls
echo.
echo.
echo !INDENT!!C_BLUE!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_BLUE!│!C_WHITE!                 STEAM ^& MILLENNIUM CONTROLS                  !C_BLUE!│!C_RESET!
echo !INDENT!!C_BLUE!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
set "MV_DISP=-"
if "!MILL_STATE!"=="ok" if defined MILL_VER set "MV_DISP=v!MILL_VER!"
set "MV_DISP=!MV_DISP!              "
set "MA_DISP=!MILL_PLUGINS! plugins"
if "!MILL_PLUGINS!"=="1" set "MA_DISP=1 plugin"
if "!MILL_THEMES!"=="1" (set "MA_DISP=!MA_DISP!, 1 theme") else set "MA_DISP=!MA_DISP!, !MILL_THEMES! themes"
echo !INDENT!  !STEAM_DOT! Steam     : !STEAM_TXT!   !MILL_DOT! Millennium: !MILL_TXT!
echo !INDENT!  !C_WHITE!●!C_RESET! Version   : !C_CYAN!!MV_DISP:~0,14!!C_RESET!   !C_WHITE!●!C_RESET! Add-ons   : !C_CYAN!!MA_DISP!!C_RESET!
if not exist "!STEAM_DIR!\steam.exe" echo !INDENT!  !C_RED![^^!] Steam was not found - get it from steampowered.com!C_RESET!
if defined MILL_UPD echo !INDENT!  !C_YELLOW!● Millennium v!MILL_UPD! is available - use [1] Install / Update!C_RESET!
if "!MILL_STATE!"=="broken" echo !INDENT!  !C_YELLOW!● Millennium is damaged - [1] Install / Update repairs it!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GREEN!1!C_WHITE!]  !C_GREEN!Install / Update!C_WHITE!    Latest Signed Release from GitHub!C_RESET!
echo !INDENT!  !C_WHITE![!C_MAGENTA!2!C_WHITE!]  !C_MAGENTA!Restart Steam!C_WHITE!       Reload Steam to Apply Changes!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_YELLOW!3!C_WHITE!]  !C_YELLOW!Manage Add-ons!C_WHITE!      Plugins On / Off, Pick Theme, Delete!C_RESET!
echo !INDENT!  !C_WHITE![!C_YELLOW!4!C_WHITE!]  !C_YELLOW!Open Folder!C_WHITE!         Open the millennium Folder!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!5!C_WHITE!]  !C_CYAN!Clean Cache!C_WHITE!         Clear Steam Web Cache - Login Is Kept!C_RESET!
echo !INDENT!  !C_WHITE![!C_RED!6!C_WHITE!]  !C_RED!Uninstall!C_WHITE!           Remove Millennium, Keep Your Add-ons!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back!C_WHITE!                Return to Main Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "STM_CHOICE="
set /p "STM_CHOICE=!PROMPT_INDENT!!C_BLUE!›!C_WHITE! Select an action [0-6]: !C_RESET!"
if not defined STM_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_STEAM
)
set "NO_INPUT_COUNT=0"
set "STM_CHOICE=!STM_CHOICE: =!"
if "!STM_CHOICE!"=="1" goto ACTION_MILL_INSTALL
if "!STM_CHOICE!"=="2" goto ACTION_STEAM_RESTART
if "!STM_CHOICE!"=="3" goto ACTION_MILL_MANAGE
if "!STM_CHOICE!"=="4" (
    if not exist "!STEAM_DIR!\millennium\" mkdir "!STEAM_DIR!\millennium" 2>nul
    start "" explorer.exe "!STEAM_DIR!\millennium"
    goto MENU_STEAM
)
if "!STM_CHOICE!"=="5" goto ACTION_STEAM_CLEAN_CACHE
if "!STM_CHOICE!"=="6" goto ACTION_MILL_UNINSTALL
if "!STM_CHOICE!"=="0" goto MAIN_MENU
if /i "!STM_CHOICE!"=="b" goto MAIN_MENU
goto MENU_STEAM

:ACTION_MILL_INSTALL
echo.
set "RC=1"
set "LOG_ACTION=Millennium"
set "LOG_RESULT=failed - Steam not found"
if not exist "!STEAM_DIR!\steam.exe" (
    echo !INDENT!  !C_RED![ERROR] Steam was not found in "!STEAM_DIR!".!C_RESET!
    goto FINISH_STEAM
)
:: PowerShell records the outcome in the history itself from here on
set "LOG_ACTION="
call :SPINNER_STEP "Checking the latest Millennium release..."
call :MILL_INSTALL_STEPS
set "RC=!errorlevel!"
if "!RC!"=="10" set "RC=0"
goto FINISH_STEAM

:MILL_INSTALL_STEPS
:: Shared by the menu and Repair. Download and verification run while Steam is still open;
:: Steam is only closed once there is a verified release to copy in.
:: Returns 0 installed, 10 already up to date, 1 failed.
set "SWX_MILL_MODE=prepare"
call :RUN_PS MILLENNIUM
set "MILL_RC=!errorlevel!"
if not "!MILL_RC!"=="0" exit /b !MILL_RC!
call :SNAPSHOT millennium
call :SPINNER_STEP "Closing Steam..."
call :KILL_STEAM
set "SWX_MILL_MODE=apply"
call :RUN_PS MILLENNIUM
set "MILL_RC=!errorlevel!"
call :START_UPDATE_CHECK fresh
call :RESTART_STEAM_PROC
exit /b !MILL_RC!

:ACTION_MILL_MANAGE
if not exist "!STEAM_DIR!\millennium\" (
    echo.
    echo !INDENT!  !C_YELLOW![^^!] Millennium is not installed - use [1] Install / Update.!C_RESET!
    call :CENTER_PAUSE
    goto MENU_STEAM
)
set "SWX_MILL_PENDING=%TEMP%\swarlex-mill-pending.json"
del /f /q "!SWX_MILL_PENDING!" >nul 2>&1
call :RUN_PS MILLMANAGE
if not "!errorlevel!"=="3" goto MENU_STEAM
echo.
echo.
call :SNAPSHOT millennium
call :SPINNER_STEP "Closing Steam to apply the changes..."
call :KILL_STEAM
call :RUN_PS MILLAPPLY
:: Add-on changes only show after a restart, so Steam comes back if it was open
call :RESTART_STEAM_PROC
call :CENTER_PAUSE
goto MENU_STEAM

:ACTION_STEAM_RESTART
echo.
if not exist "!STEAM_DIR!\steam.exe" (
    echo !INDENT!  !C_RED![ERROR] Steam was not found in "!STEAM_DIR!".!C_RESET!
    call :CENTER_PAUSE
    goto MENU_STEAM
)
call :SPINNER_STEP "Restarting Steam..."
call :KILL_STEAM
set "STEAM_KILLED="
call :START_STEAM
echo !INDENT!  !C_GREEN![+] Steam restarted.!C_RESET!
call :DLOG INFO "Restarted Steam"
call :CENTER_PAUSE
goto MENU_STEAM

:ACTION_STEAM_CLEAN_CACHE
echo.
echo !INDENT!  !C_CYAN![i] Clears Steam's web cache. Your login is kept.!C_RESET!
set "CONFIRM_SCACHE="
set /p "CONFIRM_SCACHE=!PROMPT_INDENT!Clean Steam cache? [Y/N]: "
if /i "!CONFIRM_SCACHE!"=="yes" set "CONFIRM_SCACHE=y"
if /i not "!CONFIRM_SCACHE!"=="y" goto MENU_STEAM
call :SPINNER_STEP "Cleaning Steam web cache..."
call :KILL_STEAM
call :RUN_PS STEAMCACHE
call :RESTART_STEAM_PROC
call :CENTER_PAUSE
goto MENU_STEAM

:ACTION_MILL_UNINSTALL
echo.
echo !INDENT!  !C_YELLOW![^^!] Removes Millennium. Themes, plugins and settings stay.!C_RESET!
set "CONFIRM_MUN="
set /p "CONFIRM_MUN=!PROMPT_INDENT!Uninstall Millennium? [Y/N]: "
if /i "!CONFIRM_MUN!"=="yes" set "CONFIRM_MUN=y"
if /i not "!CONFIRM_MUN!"=="y" goto MENU_STEAM
set "RC=1"
call :SPINNER_STEP "Closing Steam..."
call :KILL_STEAM
set "SWX_MILL_MODE=uninstall"
call :RUN_PS MILLENNIUM
if not errorlevel 1 set "RC=0"
call :START_UPDATE_CHECK fresh
call :RESTART_STEAM_PROC
goto FINISH_STEAM

:FINISH_STEAM
call :FLUSH_LOG
if defined CLI_MODE exit /b !RC!
call :CENTER_PAUSE
goto MENU_STEAM

:KILL_STEAM
:: Asks Steam to shut down cleanly first (it saves cloud data and settings on the way out) and only
:: forces it after 20 seconds. ping is the delay because timeout fails when input is redirected.
call :PROBE_PROCS
set "STEAM_KILLED=1"
set "STEAM_WAS_RUNNING="
if not defined RUN_Steam exit /b 0
set "STEAM_WAS_RUNNING=1"
start "" "!STEAM_DIR!\steam.exe" -shutdown
set "STEAM_WAIT=0"
:KILL_STEAM_WAIT
ping -n 2 127.0.0.1 >nul 2>&1
tasklist /NH /FI "IMAGENAME eq steam.exe" 2>nul | findstr /i "steam.exe" >nul || goto KILL_STEAM_GONE
set /a STEAM_WAIT+=1
if !STEAM_WAIT! LSS 20 goto KILL_STEAM_WAIT
call :DLOG WARN "Steam did not close within 20 seconds - forcing it"
taskkill /F /IM steam.exe /IM steamwebhelper.exe /T >nul 2>&1
ping -n 3 127.0.0.1 >nul 2>&1
:KILL_STEAM_GONE
exit /b 0

:RESTART_STEAM_PROC
:: Same rules as RESTART_DISCORD_PROC
if not defined STEAM_KILLED exit /b 0
set "STEAM_KILLED="
if /i "!CFG_RELAUNCH!"=="never" exit /b 0
if /i not "!CFG_RELAUNCH!"=="always" if not defined STEAM_WAS_RUNNING exit /b 0
call :SPINNER_STEP "Relaunching Steam..."
call :START_STEAM
exit /b 0

:START_STEAM
:: explorer.exe starts it with normal rights when Swarlex itself runs as Administrator
if not exist "!STEAM_DIR!\steam.exe" exit /b 1
if "!IS_ADMIN!"=="1" (
    start "" explorer.exe "!STEAM_DIR!\steam.exe"
) else (
    start "" "!STEAM_DIR!\steam.exe"
)
exit /b 0

:SPICETIFY
:: Runs spicetify with these arguments; its output is indented and coloured like the rest of Swarlex
call :RUN_TOOL spicetify %*
exit /b !errorlevel!

:RUN_TOOL
:: Args: program, then its arguments. Output indented and coloured like the rest of Swarlex, with a
:: spinner while it works. Returns the program's exit code. Only for tools that never ask questions:
:: their output is shown once they finish.
set "SWX_TOOL_EXE=%~1"
set "SWX_TOOL_ARGS="
:: Everything after the program name, quotes kept as they are ("for /f" would trip over quoted paths)
if not "%~2"=="" (
    set "SWX_TOOL_ARGS=%*"
    set "SWX_TOOL_ARGS=!SWX_TOOL_ARGS:*%~1 =!"
)
call :RUN_PS TOOLRUN
exit /b !errorlevel!

:SNAPSHOT
:: Arg: vencord / spicetify / millennium. Saves what the coming change can touch so Backup > Undo
:: can roll it back. Never fails the caller.
set "SWX_SNAP_KIND=%~1"
call :RUN_PS BACKUP
set "SWX_SNAP_KIND="
exit /b 0

:: -------------------------------------------------------------
:: PROFILE BACKUP AND RESTORE
:: -------------------------------------------------------------
:MENU_BACKUP
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_MAGENTA!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_MAGENTA!│!C_WHITE!                FULL PROFILE BACKUP ^& RESTORE                 !C_MAGENTA!│!C_RESET!
echo !INDENT!!C_MAGENTA!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
echo !INDENT!  !C_GRAY!Archive Vencord, userplugins, Spicetify ^& Millennium data!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GREEN!1!C_WHITE!]  !C_GREEN!Backup Profile!C_WHITE!      Create Desktop .zip Archive!C_RESET!
echo !INDENT!  !C_WHITE![!C_YELLOW!2!C_WHITE!]  !C_YELLOW!Restore Profile!C_WHITE!     Restore from Latest Desktop .zip!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_RED!3!C_WHITE!]  !C_RED!Undo Last Update!C_WHITE!    Roll Back from a Safety Snapshot!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back!C_WHITE!                Return to Main Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "B_CHOICE="
set /p "B_CHOICE=!PROMPT_INDENT!!C_MAGENTA!›!C_WHITE! Select an option [0-3]: !C_RESET!"
if not defined B_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_BACKUP
)
set "NO_INPUT_COUNT=0"
set "B_CHOICE=!B_CHOICE: =!"
if "!B_CHOICE!"=="1" goto ACTION_BACKUP_PROFILE
if "!B_CHOICE!"=="2" goto ACTION_RESTORE_PROFILE
if "!B_CHOICE!"=="3" goto ACTION_UNDO_SNAPSHOT
if "!B_CHOICE!"=="0" goto MAIN_MENU
if /i "!B_CHOICE!"=="b" goto MAIN_MENU
goto MENU_BACKUP

:ACTION_BACKUP_PROFILE
echo.
set "RC=1"
call :SPINNER_STEP "Archiving your profile to the Desktop..."
set "SWX_DESK=!DESK_DIR!"
call :RUN_PS BACKUP
if not errorlevel 1 set "RC=0"
goto FINISH_BACKUP

:ACTION_RESTORE_PROFILE
echo.
set "RC=1"
call :SPINNER_STEP "Scanning for latest backup file..."
set "LATEST_ZIP="
for /f "delims=" %%F in ('dir /b /a-d /o-d "!DESK_DIR!\Swarlex_Backup_*.zip" 2^>nul') do (
    if not defined LATEST_ZIP set "LATEST_ZIP=!DESK_DIR!\%%F"
)
if not defined LATEST_ZIP (
    echo.
    echo !INDENT!  !C_RED![^^!] No Swarlex_Backup_*.zip file found on Desktop.!C_RESET!
    goto FINISH_BACKUP
)
echo !INDENT!  !C_CYAN![*] Found latest backup: !LATEST_ZIP!!C_RESET!
echo !INDENT!  !C_YELLOW![^^!] This replaces your Vencord, Spicetify and Millennium data.!C_RESET!
echo.
set "DO_REST="
set /p "DO_REST=!PROMPT_INDENT!Proceed with restore? [Y/N]: "
if /i "!DO_REST!"=="yes" set "DO_REST=y"
if /i not "!DO_REST!"=="y" (
    if defined CLI_MODE exit /b 1
    goto MENU_BACKUP
)

call :SPINNER_STEP "Restoring configuration files..."
call :KILL_DISCORD all
call :KILL_SPOTIFY
:: Steam only has to close when Millennium is in use - it rewrites its config on exit
if exist "!STEAM_DIR!\millennium\" call :KILL_STEAM
set "SWX_ZIP=!LATEST_ZIP!"
set "SWX_RESTORED_FILE=%TEMP%\swarlex-restored.txt"
del /f /q "!SWX_RESTORED_FILE!" >nul 2>&1
call :RUN_PS RESTORE
if not errorlevel 1 (
    set "RC=0"
    rem Restored files alone change nothing in Spotify and Steam - make the setup active again
    findstr /x /i "spicetify" "!SWX_RESTORED_FILE!" >nul 2>&1 && call :RESTORE_APPLY_SPICETIFY
    findstr /x /i "millennium" "!SWX_RESTORED_FILE!" >nul 2>&1 && call :RESTORE_CHECK_MILLENNIUM
)
del /f /q "!SWX_RESTORED_FILE!" >nul 2>&1
set "SWX_RESTORED_FILE="
call :RESTART_DISCORD_PROC
call :RESTART_SPOTIFY_PROC
call :RESTART_STEAM_PROC
goto FINISH_BACKUP

:RESTORE_APPLY_SPICETIFY
echo.
call :ENSURE_SPOTIFY_TOOLS
if errorlevel 1 exit /b 1
call :SPINNER_STEP "Applying the restored Spicetify setup..."
call :SPICETIFY apply !SPICETIFY_FLAGS!
if errorlevel 1 call :SPICETIFY backup apply !SPICETIFY_FLAGS!
if errorlevel 1 (
    echo !INDENT!  !C_YELLOW![^^!] Not applied - use Spotify, [1] Apply Spicetify.!C_RESET!
    call :DLOG WARN "Restore: Spicetify could not be applied"
    exit /b 1
)
echo !INDENT!  !C_GREEN![+] Spicetify applied - your themes and extensions are back.!C_RESET!
:: spicetify apply starts Spotify itself
set "SPOTIFY_KILLED="
call :START_SPOTIFY_PROC
exit /b 0

:RESTORE_CHECK_MILLENNIUM
if exist "!STEAM_DIR!\wsock32.dll" if exist "!STEAM_DIR!\millennium\lib\millennium.dll" exit /b 0
if not exist "!STEAM_DIR!\steam.exe" exit /b 0
echo.
echo !INDENT!  !C_YELLOW![^^!] Millennium is not installed - the add-ons need it.!C_RESET!
set "DO_MILL="
set /p "DO_MILL=!PROMPT_INDENT!Install Millennium now? [Y/N]: "
if /i "!DO_MILL!"=="yes" set "DO_MILL=y"
if /i not "!DO_MILL!"=="y" (
    echo !INDENT!  !C_GRAY!Later: Steam, [1] Install / Update.!C_RESET!
    exit /b 0
)
:: The install closes and reopens Steam itself; remember whether it was open before the restore
set "MILL_PREV_OPEN=!STEAM_WAS_RUNNING!"
call :SPINNER_STEP "Checking the latest Millennium release..."
call :MILL_INSTALL_STEPS
if defined MILL_PREV_OPEN (
    set "STEAM_KILLED=1"
    set "STEAM_WAS_RUNNING=1"
)
set "MILL_PREV_OPEN="
exit /b 0

:ACTION_UNDO_SNAPSHOT
echo.
set "SWX_SNAP_PICK=%TEMP%\swarlex-snap-pick.txt"
del /f /q "!SWX_SNAP_PICK!" >nul 2>&1
call :RUN_PS SNAPLIST
if errorlevel 1 (
    call :CENTER_PAUSE
    goto MENU_BACKUP
)
echo.
set "SNAP_N="
set "SNAP_ZIP="
set /p "SNAP_N=!PROMPT_INDENT!!C_MAGENTA!›!C_WHITE! Roll back to [number, Enter = cancel]: !C_RESET!"
if defined SNAP_N set "SNAP_N=!SNAP_N: =!"
if defined SNAP_N echo(!SNAP_N!| findstr /r "^[1-9][0-9]*$" >nul && call :SNAP_PICK_LINE !SNAP_N!
del /f /q "!SWX_SNAP_PICK!" >nul 2>&1
if not defined SNAP_N goto MENU_BACKUP
if not defined SNAP_ZIP (
    echo !INDENT!  !C_RED![x] There is no snapshot "!SNAP_N!".!C_RESET!
    call :CENTER_PAUSE
    goto MENU_BACKUP
)
for %%Z in ("!SNAP_ZIP!") do set "SNAP_NAME=%%~nZ"
for /f "delims=_" %%K in ("!SNAP_NAME!") do set "SNAP_KIND=%%K"
echo.
if /i "!SNAP_KIND!"=="vencord" echo !INDENT!  !C_YELLOW![^^!] Vencord settings, plugins and source go back to then.!C_RESET!
if /i "!SNAP_KIND!"=="spicetify" echo !INDENT!  !C_YELLOW![^^!] Spicetify settings go back to then; the CLI stays as is.!C_RESET!
if /i "!SNAP_KIND!"=="millennium" echo !INDENT!  !C_YELLOW![^^!] Millennium settings, plugins and themes go back to then.!C_RESET!
set "DO_UNDO="
set /p "DO_UNDO=!PROMPT_INDENT!Roll back now? [Y/N]: "
if /i "!DO_UNDO!"=="yes" set "DO_UNDO=y"
if /i not "!DO_UNDO!"=="y" goto MENU_BACKUP
set "RC=1"
call :SPINNER_STEP "Rolling back..."
if /i "!SNAP_KIND!"=="vencord" call :KILL_DISCORD all
if /i "!SNAP_KIND!"=="spicetify" call :KILL_SPOTIFY
if /i "!SNAP_KIND!"=="millennium" call :KILL_STEAM
set "SWX_ZIP=!SNAP_ZIP!"
set "SWX_RESTORE_LABEL=Undo update"
set "SWX_ROLLBACK_FILE=%TEMP%\swarlex-rollback-head.txt"
del /f /q "!SWX_ROLLBACK_FILE!" >nul 2>&1
call :RUN_PS RESTORE
set "UNDO_RC=!errorlevel!"
set "SWX_RESTORE_LABEL="
if "!UNDO_RC!"=="0" set "RC=0"
if "!UNDO_RC!"=="0" if exist "!SWX_ROLLBACK_FILE!" call :UNDO_VENCORD_SOURCE
set "SWX_ROLLBACK_FILE="
call :RESTART_DISCORD_PROC
call :RESTART_SPOTIFY_PROC
call :RESTART_STEAM_PROC
goto FINISH_BACKUP

:SNAP_PICK_LINE
:: Arg: 1-based line number in SWX_SNAP_PICK. "for /f skip" needs a literal number, hence a subroutine.
set /a "SNAP_SKIP=%~1-1"
if !SNAP_SKIP! EQU 0 (
    set /p "SNAP_ZIP=" < "!SWX_SNAP_PICK!"
    exit /b 0
)
for /f "usebackq skip=%SNAP_SKIP% delims=" %%Z in ("!SWX_SNAP_PICK!") do if not defined SNAP_ZIP set "SNAP_ZIP=%%Z"
exit /b 0

:UNDO_VENCORD_SOURCE
:: "reset --keep" moves the branch back but refuses instead of overwriting local source edits
set "ROLL_HEAD="
set /p "ROLL_HEAD=" < "!SWX_ROLLBACK_FILE!"
del /f /q "!SWX_ROLLBACK_FILE!" >nul 2>&1
if not defined ROLL_HEAD exit /b 0
set "CUR_HEAD="
for /f %%H in ('git -C "!VENCORD_DIR!" rev-parse HEAD 2^>nul') do set "CUR_HEAD=%%H"
if /i "!CUR_HEAD!"=="!ROLL_HEAD!" exit /b 0
git -C "!VENCORD_DIR!" reset -q --keep !ROLL_HEAD!
if errorlevel 1 (
    set "RC=1"
    echo !INDENT!  !C_RED![ERROR] Vencord source not rolled back - local edits conflict.!C_RESET!
    call :LOG "Undo update" "failed - Vencord source has conflicting local edits"
    exit /b 1
)
echo !INDENT!  !C_GREEN![+] Vencord source rolled back to !ROLL_HEAD:~0,7!.!C_RESET!
call :BUILD_VENCORD
if errorlevel 1 (
    set "RC=1"
    call :LOG "Undo update" "failed - rolled back to !ROLL_HEAD:~0,7! but the build failed"
    exit /b 1
)
call :PROBE_DISCORD_FLAVORS
call :PATCH_DISCORD install
if errorlevel 1 (
    set "RC=1"
    call :LOG "Undo update" "failed - rolled back to !ROLL_HEAD:~0,7! but could not patch Discord"
    exit /b 1
)
call :LOG "Undo update" "Vencord source rolled back to !ROLL_HEAD:~0,7! and patched"
call :START_UPDATE_CHECK fresh
exit /b 0

:FINISH_BACKUP
if defined CLI_MODE exit /b !RC!
call :CENTER_PAUSE
goto MENU_BACKUP

:: -------------------------------------------------------------
:: SETTINGS AND ACTION HISTORY
:: -------------------------------------------------------------
:MENU_SETTINGS
call :CALC_CENTER
set "SWX_UPD="
if exist "%SWX_UPDATE_FILE%" for /f "usebackq tokens=1,* delims==" %%A in ("%SWX_UPDATE_FILE%") do if /i "%%A"=="swarlex" set "SWX_UPD=%%B"
if defined SWX_UPD if "!SWX_UPD!"=="!SWX_VERSION!" set "SWX_UPD="
cls
echo.
echo.
echo !INDENT!!C_YELLOW!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_YELLOW!│!C_WHITE!                       SWARLEX SETTINGS                       !C_YELLOW!│!C_RESET!
echo !INDENT!!C_YELLOW!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
if /i "!CFG_INTRO!"=="off" (
    set "SET_INTRO_VAL=!C_YELLOW!Fast Start     !C_RESET!"
    set "SET_INTRO_DESC=!C_GRAY![0s Skip Animation]!C_RESET!"
) else (
    set "SET_INTRO_VAL=!C_GREEN!Enabled        !C_RESET!"
    set "SET_INTRO_DESC=!C_GRAY![Play Animation]!C_RESET!"
)

if /i "!CFG_RELAUNCH!"=="always" (
    set "SET_REL_VAL=!C_GREEN!Always         !C_RESET!"
    set "SET_REL_DESC=!C_GRAY![Always Restart]!C_RESET!"
) else if /i "!CFG_RELAUNCH!"=="never" (
    set "SET_REL_VAL=!C_GRAY!Never          !C_RESET!"
    set "SET_REL_DESC=!C_GRAY![Keep Closed]!C_RESET!"
) else (
    set "SET_REL_VAL=!C_CYAN!If It Was Open !C_RESET!"
    set "SET_REL_DESC=!C_GRAY![Restart If Open]!C_RESET!"
)

if /i "!CFG_ADMIN!"=="on" (
    set "SET_ADM_VAL=!C_MAGENTA!On             !C_RESET!"
    set "SET_ADM_DESC=!C_GRAY![UAC On Launch]!C_RESET!"
) else (
    set "SET_ADM_VAL=!C_GRAY!Off            !C_RESET!"
    set "SET_ADM_DESC=!C_GRAY![Normal Launch]!C_RESET!"
)

if "!IS_ADMIN!"=="1" (
    set "SET_ELV_KEY=!C_GRAY!4"
    set "SET_ELV_NAME=!C_GRAY!Run As Admin Now    "
    set "SET_ELV_VAL=!C_MAGENTA!Already Active   "
    set "SET_ELV_DESC=!C_GRAY![Administrator]!C_RESET!"
) else (
    set "SET_ELV_KEY=!C_MAGENTA!4"
    set "SET_ELV_NAME=!C_MAGENTA!Run As Admin Now    "
    set "SET_ELV_VAL=!C_WHITE!Reopen Swarlex   "
    set "SET_ELV_DESC=!C_GRAY![UAC Prompt]!C_RESET!"
)
echo !INDENT!  !PRIV_DOT! Privilege : !PRIV_TXT!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
echo !INDENT!  !C_WHITE![!C_YELLOW!1!C_WHITE!]  !C_YELLOW!Startup Intro       !C_WHITE!!SET_INTRO_VAL!  !SET_INTRO_DESC!
echo !INDENT!  !C_WHITE![!C_YELLOW!2!C_WHITE!]  !C_YELLOW!Auto-Relaunch       !C_WHITE!!SET_REL_VAL!  !SET_REL_DESC!
echo.
echo !INDENT!  !C_WHITE![!C_MAGENTA!3!C_WHITE!]  !C_MAGENTA!Start As Admin      !C_WHITE!!SET_ADM_VAL!  !SET_ADM_DESC!
echo !INDENT!  !C_WHITE![!SET_ELV_KEY!!C_WHITE!]  !SET_ELV_NAME!!SET_ELV_VAL!!SET_ELV_DESC!
echo.
echo !INDENT!  !C_WHITE![!C_CYAN!5!C_WHITE!]  !C_CYAN!Action History      !C_WHITE!Audit Log        !C_GRAY![Recent Activity]!C_RESET!
echo !INDENT!  !C_WHITE![!C_CYAN!6!C_WHITE!]  !C_CYAN!Log File            !C_WHITE!swarlex.log      !C_GRAY![Open In Notepad]!C_RESET!
echo !INDENT!  !C_WHITE![!C_CYAN!7!C_WHITE!]  !C_CYAN!System Info         !C_WHITE!All Versions     !C_GRAY![Copy For Support]!C_RESET!
echo.
set "SU_VAL=v!SWX_VERSION! Latest                 "
set "SU_DESC=!C_GRAY![Check Now]!C_RESET!"
set "SU_COL=!C_WHITE!"
if defined SWX_UPD (
    set "SU_VAL=v!SWX_UPD! Ready                 "
    set "SU_DESC=!C_GRAY![Install Now]!C_RESET!"
    set "SU_COL=!C_YELLOW!"
)
echo !INDENT!  !C_WHITE![!C_GREEN!8!C_WHITE!]  !C_GREEN!Swarlex Update      !SU_COL!!SU_VAL:~0,17!!SU_DESC!
if /i "!CFG_AUTOUPD!"=="on" (
    echo !INDENT!  !C_WHITE![!C_GREEN!9!C_WHITE!]  !C_GREEN!Auto-Update         !C_GREEN!On               !C_GRAY![Install On Start]!C_RESET!
) else (
    echo !INDENT!  !C_WHITE![!C_GREEN!9!C_WHITE!]  !C_GREEN!Auto-Update         !C_GRAY!Off              !C_GRAY![Ask First]!C_RESET!
)
echo.
echo !INDENT!  !C_WHITE![!C_GRAY!0!C_WHITE!]  !C_GRAY!Back                !C_WHITE!Return to Main Menu!C_RESET!
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
echo.
set "ST_CHOICE="
set /p "ST_CHOICE=!PROMPT_INDENT!!C_YELLOW!›!C_WHITE! Select an option [0-9]: !C_RESET!"
if not defined ST_CHOICE (
    call :NO_INPUT || goto EXIT_SCRIPT
    goto MENU_SETTINGS
)
set "NO_INPUT_COUNT=0"
set "ST_CHOICE=!ST_CHOICE: =!"
if "!ST_CHOICE!"=="1" (
    if /i "!CFG_INTRO!"=="off" (set "CFG_INTRO=on") else (set "CFG_INTRO=off")
    call :SAVE_SETTINGS
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="2" (
    if /i "!CFG_RELAUNCH!"=="always" (set "CFG_RELAUNCH=never") else if /i "!CFG_RELAUNCH!"=="never" (set "CFG_RELAUNCH=ifopen") else (set "CFG_RELAUNCH=always")
    call :SAVE_SETTINGS
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="3" (
    if /i "!CFG_ADMIN!"=="on" (set "CFG_ADMIN=off") else (set "CFG_ADMIN=on")
    call :SAVE_SETTINGS
    call :DLOG INFO "Start As Admin set to !CFG_ADMIN!"
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="5" goto MENU_HISTORY
if "!ST_CHOICE!"=="7" goto MENU_SYSINFO
if "!ST_CHOICE!"=="8" goto ACTION_SELF_UPDATE
if "!ST_CHOICE!"=="9" (
    if /i "!CFG_AUTOUPD!"=="on" (set "CFG_AUTOUPD=off") else (set "CFG_AUTOUPD=on")
    call :SAVE_SETTINGS
    call :DLOG INFO "Auto-Update set to !CFG_AUTOUPD!"
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="6" (
    if not exist "!SWX_LOGFILE!" type nul > "!SWX_LOGFILE!"
    start "" notepad.exe "!SWX_LOGFILE!"
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="4" if "!IS_ADMIN!"=="0" (
    echo.
    call :ELEVATE settings
    if not errorlevel 1 goto SWX_QUIT
    call :CENTER_PAUSE
    goto MENU_SETTINGS
)
if "!ST_CHOICE!"=="0" goto MAIN_MENU
if /i "!ST_CHOICE!"=="b" goto MAIN_MENU
goto MENU_SETTINGS

:MENU_HISTORY
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                        ACTION HISTORY                        !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
call :RUN_PS HISTORYVIEW
call :CENTER_PAUSE
goto MENU_SETTINGS

:AUTO_SELF_UPDATE
:: Returns 0 only when the new version is downloaded, verified and about to replace this window.
:: Asks GitHub at every start (a few hundred ms, silent when there is nothing new or no internet),
:: so a new version is installed the first time Swarlex is opened after its release.
set "SWX_SU_MODE=auto"
:: Quick look first: curl (part of Windows 10 1803 and later) reads the latest tag from GitHub's
:: redirect in ~0.1 s. When that is this version - most starts - PowerShell is not needed at all.
:: Anything else (a newer tag, a renamed repository, no answer) goes through the full check below.
set "SU_TAG="
if exist "%SystemRoot%\System32\curl.exe" for /f "delims=" %%U in ('""%SystemRoot%\System32\curl.exe" -s -m 6 -o NUL -w "%%{redirect_url}" "https://github.com/!SWX_REPO!/releases/latest" 2^>nul"') do set "SU_TAG=%%U"
if defined SU_TAG set "SU_TAG=!SU_TAG:*/releases/tag/=!"
if defined SU_TAG if /i "!SU_TAG!"=="v!SWX_VERSION!" exit /b 1
call :RUN_PS SELFUPDATE
set "SU_RC=!errorlevel!"
if "!SU_RC!"=="10" exit /b 1
if "!SU_RC!"=="11" exit /b 1
if not "!SU_RC!"=="0" (
    echo !INDENT!  !C_GRAY!Staying on v!SWX_VERSION! - retry from Settings, [8].!C_RESET!
    ping -n 5 127.0.0.1 >nul 2>&1
    exit /b 1
)
ping -n 2 127.0.0.1 >nul 2>&1
start "" /min cmd /d /c "%TEMP%\swarlex-selfupdate-run.cmd"
exit /b 0

:ACTION_SELF_UPDATE
echo.
call :SPINNER_STEP "Checking GitHub for a new Swarlex version..."
set "SWX_SU_MODE=check"
call :RUN_PS SELFUPDATE
set "SU_RC=!errorlevel!"
if "!SU_RC!"=="10" (
    call :START_UPDATE_CHECK fresh
    call :CENTER_PAUSE
    goto MENU_SETTINGS
)
if not "!SU_RC!"=="0" (
    call :CENTER_PAUSE
    goto MENU_SETTINGS
)
echo.
set "DO_SU="
set /p "DO_SU=!PROMPT_INDENT!Install it now? Swarlex closes and reopens by itself. [Y/N]: "
if /i "!DO_SU!"=="yes" set "DO_SU=y"
if /i not "!DO_SU!"=="y" goto MENU_SETTINGS
call :SPINNER_STEP "Downloading and verifying the update..."
set "SWX_SU_MODE=install"
call :RUN_PS SELFUPDATE
if errorlevel 1 (
    call :CENTER_PAUSE
    goto MENU_SETTINGS
)
:: The helper swaps the file only after this window is gone - a running batch file must not change
ping -n 2 127.0.0.1 >nul 2>&1
start "" /min cmd /d /c "%TEMP%\swarlex-selfupdate-run.cmd"
goto SWX_QUIT

:MENU_SYSINFO
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                         SYSTEM INFO                          !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
set "SWX_SYSINFO_FILE=%TEMP%\swarlex-sysinfo.txt"
call :RUN_PS SYSINFO
echo.
set "SI_CHOICE="
set /p "SI_CHOICE=!PROMPT_INDENT!!C_YELLOW!›!C_WHITE! C = copy to clipboard, Enter = back: !C_RESET!"
if /i "!SI_CHOICE!"=="c" if exist "!SWX_SYSINFO_FILE!" (
    call :RUN_PS SYSCOPY
    call :CENTER_PAUSE
)
del /f /q "!SWX_SYSINFO_FILE!" >nul 2>&1
goto MENU_SETTINGS

:: -------------------------------------------------------------
:: ADMINISTRATOR RIGHTS
:: -------------------------------------------------------------
:ELEVATE
:: Reopens Swarlex with Administrator rights (UAC prompt). Arg: menu the new window opens.
:: Returns 0 once the elevated window has started; the caller then closes this one with SWX_QUIT.
set "SWX_ELEVATE_ARG=--elevated %~1"
call :DLOG INFO "Requesting Administrator rights [UAC]"
powershell -NoProfile -NonInteractive -Command "try { Start-Process -FilePath $env:SWX_SELF -ArgumentList $env:SWX_ELEVATE_ARG.Trim() -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if errorlevel 1 (
    call :DLOG WARN "Administrator request was declined - continuing with standard rights"
    echo !INDENT!  !C_YELLOW![^^!] Admin request declined - continuing with standard rights.!C_RESET!
    exit /b 1
)
call :DLOG INFO "Elevated window started - this window closes"
exit /b 0

:OFFER_ELEVATE
:: Arg: menu to reopen. Asks first; returns 0 only when the elevated window started.
echo.
set "DO_ELEV="
set /p "DO_ELEV=!PROMPT_INDENT!!C_YELLOW!Reopen Swarlex as Administrator and try again? [Y/N]: !C_RESET!"
if /i "!DO_ELEV!"=="yes" set "DO_ELEV=y"
if /i not "!DO_ELEV!"=="y" exit /b 1
call :ELEVATE %~1
exit /b !errorlevel!

:SWX_QUIT
:: Closes without the goodbye screen because another Swarlex window took over
call :SWX_END 0
exit /b 0

:SWX_END
:: Arg: exit code. A window that runs Swarlex as "cmd /k Swarlex-Manager.bat" (what "start" makes of a
:: .bat - older update helpers reopened Swarlex like that) would stay open at a prompt after Swarlex ends,
:: so that window is closed too. A terminal the user opened and ran Swarlex in is left alone.
set "SWX_CCL=!cmdcmdline!"
if /i not "!SWX_CCL:/k=!"=="!SWX_CCL!" if /i not "!SWX_CCL:%SWX_SELF_NAME%=!"=="!SWX_CCL!" exit %~1
exit /b %~1

:: -------------------------------------------------------------
:: ONE-CLICK REPAIR
:: REPAIRSCAN only looks; it lists what it wants fixed in SWX_REPAIR_FILE
:: and the fixes run here so they reuse the normal install/build/patch code.
:: -------------------------------------------------------------
:ACTION_REPAIR
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_RED!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_RED!│!C_WHITE!                   S Y S T E M   R E P A I R                  !C_RED!│!C_RESET!
echo !INDENT!!C_RED!│!C_GRAY!             Scan ^& Fix Discord, Spotify ^& Steam              !C_RED!│!C_RESET!
echo !INDENT!!C_RED!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
set "RC=1"
set "LOG_ACTION=Repair"
set "LOG_RESULT=failed - the scan did not finish"
call :SPINNER_STEP "Scanning Discord, Spotify and Steam..."
call :RUN_PS REPAIRSCAN
set "REPAIR_COUNT=!errorlevel!"
if !REPAIR_COUNT! GEQ 99 goto FINISH_REPAIR
if !REPAIR_COUNT! EQU 0 (
    set "RC=0"
    set "LOG_RESULT=nothing to fix"
    goto FINISH_REPAIR
)
if "!REPAIR_COUNT!"=="1" (set "PR_WORD=problem") else set "PR_WORD=problems"
echo.
if defined CLI_MODE goto REPAIR_APPLY
set "DO_REPAIR="
set /p "DO_REPAIR=!PROMPT_INDENT!!C_RED!›!C_WHITE! Fix !REPAIR_COUNT! !PR_WORD! now? [Enter = Yes / N = No]: !C_RESET!"
if /i "!DO_REPAIR!"=="no" set "DO_REPAIR=n"
if /i "!DO_REPAIR!"=="n" (
    set "LOG_RESULT=found !REPAIR_COUNT! !PR_WORD!, not fixed"
    goto FINISH_REPAIR
)

:REPAIR_APPLY
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
call :REPAIR_RUN
echo.
echo !INDENT!!C_GRAY!────────────────────────────────────────────────────────────────!C_RESET!
call :SPINNER_STEP "Checking again..."
call :RUN_PS REPAIRSCAN
set "REPAIR_LEFT=!errorlevel!"
if !REPAIR_LEFT! GEQ 99 (
    set "LOG_RESULT=ran !FIX_DONE! fix[es], the re-check failed"
    goto FINISH_REPAIR
)
set /a "REPAIR_FIXED=REPAIR_COUNT-REPAIR_LEFT"
if !REPAIR_FIXED! LSS 0 set "REPAIR_FIXED=0"
if !REPAIR_LEFT! EQU 0 (
    set "RC=0"
    set "LOG_RESULT=fixed !REPAIR_COUNT! !PR_WORD!"
) else (
    set "LOG_RESULT=failed - fixed !REPAIR_FIXED! of !REPAIR_COUNT!, !REPAIR_LEFT! left"
)
goto FINISH_REPAIR

:FINISH_REPAIR
call :FLUSH_LOG
if defined CLI_MODE exit /b !RC!
call :CENTER_PAUSE
goto MAIN_MENU

:REPAIR_RUN
for %%K in (tools safedir gitlock gitabort recover build patch unpatch spicetools spiceconfig spiceapply millennium settings temp) do set "FIX_%%K="
if exist "!SWX_REPAIR_FILE!" for /f "usebackq tokens=1,* delims==" %%K in ("!SWX_REPAIR_FILE!") do (
    if "%%L"=="" (set "FIX_%%K=1") else set "FIX_%%K=%%L"
)
set "FIX_DONE=0"
set "FIX_FAILED=0"
:: Order matters: tools before git and build, build before patch, the CLI before Spicetify fixes
for %%K in (tools safedir gitlock gitabort recover build patch unpatch spicetools spiceconfig spiceapply millennium settings temp) do (
    if defined FIX_%%K call :REPAIR_DO %%K
)
exit /b 0

:REPAIR_DO
set "FX=%~1"
set "FX_ARG=!FIX_%~1!"
set "FX_MSG=%~1"
if "!FX!"=="tools" set "FX_MSG=Installing missing build tools"
if "!FX!"=="safedir" set "FX_MSG=Marking the Vencord folder as trusted for git"
if "!FX!"=="gitlock" set "FX_MSG=Removing a stale git lock file"
if "!FX!"=="gitabort" set "FX_MSG=Cancelling the unfinished git !FX_ARG!"
if "!FX!"=="recover" set "FX_MSG=Putting parked userplugins back"
if "!FX!"=="build" set "FX_MSG=Rebuilding Vencord"
if "!FX!"=="patch" set "FX_MSG=Re-patching Vencord into !FX_ARG!"
if "!FX!"=="unpatch" set "FX_MSG=Removing a broken Vencord patch from !FX_ARG!"
if "!FX!"=="spicetools" set "FX_MSG=Reinstalling the Spicetify CLI"
if "!FX!"=="spiceconfig" set "FX_MSG=Pointing Spicetify at the Spotify folder"
if "!FX!"=="spiceapply" set "FX_MSG=Re-applying Spicetify after the Spotify update"
if "!FX!"=="millennium" set "FX_MSG=Reinstalling Millennium into Steam"
if "!FX!"=="settings" set "FX_MSG=Resetting invalid Swarlex settings"
if "!FX!"=="temp" set "FX_MSG=Deleting leftover temporary files"
echo.
echo !INDENT!  !C_CYAN![*] !FX_MSG!...!C_RESET!
call :REPAIR_FIX_%FX%
if errorlevel 1 (
    set /a FIX_FAILED+=1
    echo !INDENT!  !C_RED![x] Failed: !FX_MSG!!C_RESET!
    call :DLOG ERROR "Repair: !FX_MSG! - failed"
) else (
    set /a FIX_DONE+=1
    echo !INDENT!  !C_GREEN![+] Done: !FX_MSG!!C_RESET!
    call :DLOG INFO "Repair: !FX_MSG! - done"
)
exit /b 0

:REPAIR_FIX_tools
call :ENSURE_VENCORD_TOOLS
exit /b !errorlevel!

:REPAIR_FIX_safedir
:: git refuses repositories owned by another account (e.g. cloned from an elevated window)
set "SD_PATH=!VENCORD_DIR:\=/!"
git config --global --add safe.directory "!SD_PATH!"
exit /b !errorlevel!

:REPAIR_FIX_gitlock
del /f /q "!VENCORD_DIR!\.git\index.lock" 2>nul
if exist "!VENCORD_DIR!\.git\index.lock" exit /b 1
exit /b 0

:REPAIR_FIX_gitabort
if /i not "!FX_ARG!"=="merge" if /i not "!FX_ARG!"=="rebase" exit /b 1
git -C "!VENCORD_DIR!" !FX_ARG! --abort
exit /b !errorlevel!

:REPAIR_FIX_recover
set "SWX_DOCTOR_MODE=recover"
call :RUN_PS DOCTOR
exit /b !errorlevel!

:REPAIR_FIX_build
call :BUILD_VENCORD
exit /b !errorlevel!

:REPAIR_FIX_patch
set "FX_MODE=install"
goto REPAIR_PATCHER

:REPAIR_FIX_unpatch
set "FX_MODE=uninstall"

:REPAIR_PATCHER
:: FX_ARG lists the Discord builds to fix; the selected target is put back afterwards.
:: An empty list would reach PATCHER as "every build", so it is refused here.
if not defined FX_ARG exit /b 1
set "SAVED_TARGET=!SWX_TARGET_DISCORD!"
call :KILL_DISCORD all
set "SWX_TARGET_DISCORD=!FX_ARG!"
call :PATCH_DISCORD !FX_MODE!
set "FX_RC=!errorlevel!"
set "SWX_TARGET_DISCORD=!SAVED_TARGET!"
call :RESTART_DISCORD_PROC
exit /b !FX_RC!

:REPAIR_FIX_spicetools
call :ENSURE_SPOTIFY_TOOLS
exit /b !errorlevel!

:REPAIR_FIX_spiceconfig
call :SPICETIFY config spotify_path "%APPDATA%\Spotify" prefs_path "%APPDATA%\Spotify\prefs" !SPICETIFY_FLAGS!
exit /b !errorlevel!

:REPAIR_FIX_spiceapply
:: After a Spotify update the old backup no longer matches, which "restore backup apply" handles
call :KILL_SPOTIFY
call :SPICETIFY backup apply !SPICETIFY_FLAGS!
if errorlevel 1 call :SPICETIFY restore backup apply !SPICETIFY_FLAGS!
set "FX_RC=!errorlevel!"
call :RESTART_SPOTIFY_PROC
exit /b !FX_RC!

:REPAIR_FIX_millennium
:: A Steam update or verify can delete the loader; reinstall the latest verified release
set "SWX_MILL_FORCE=1"
call :MILL_INSTALL_STEPS
set "FX_RC=!errorlevel!"
set "SWX_MILL_FORCE="
exit /b !FX_RC!

:REPAIR_FIX_settings
call :SAVE_SETTINGS
exit /b 0

:REPAIR_FIX_temp
for /d %%D in ("%TEMP%\swarlex-plugin-*" "%TEMP%\swarlex-backup-*" "%TEMP%\swarlex-restore-*" "%TEMP%\swarlex-vencord-dist" "%TEMP%\swarlex-millennium") do rd /s /q "%%D" 2>nul
del /f /q "%TEMP%\swarlex-mill-pending.json" "%TEMP%\swarlex-snap-pick.txt" "%TEMP%\swarlex-rollback-head.txt" 2>nul
exit /b 0

:: -------------------------------------------------------------
:: EXIT
:: -------------------------------------------------------------
:EXIT_SCRIPT
call :DLOG INFO "Swarlex closed"
call :CALC_CENTER
cls
echo.
echo.
echo !INDENT!!C_CYAN!╭──────────────────────────────────────────────────────────────╮!C_RESET!
echo !INDENT!!C_CYAN!│!C_WHITE!                 S W A R L E X   C L O S E D                  !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!│!C_GRAY!                    Have a wonderful day.                     !C_CYAN!│!C_RESET!
echo !INDENT!!C_CYAN!╰──────────────────────────────────────────────────────────────╯!C_RESET!
echo.
timeout /t 1 >nul 2>&1
call :SWX_END 0
exit /b 0

:: =============================================================
:: EMBEDDED POWERSHELL BLOCKS - never executed by cmd.
:: Loaded by :RUN_PS, which always prepends the COMMON block.
:: =============================================================
::SWX_PS_BEGIN COMMON
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pad = ' ' * ([int]$env:SWX_PAD + 2)

# Appends to swarlex.log in the same format as the batch :DLOG; logging must never break an action
function Write-Log([string]$level, [string]$msg) {
    try {
        if (-not $env:SWX_LOGFILE) { return }
        $line = '{0} [{1,-6}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg.Trim()
        [IO.File]::AppendAllText($env:SWX_LOGFILE, $line + "`r`n", (New-Object Text.UTF8Encoding $false))
    } catch { }
}

# Red lines are errors and yellow lines warnings, so they also go to swarlex.log
function Say([string]$msg, [string]$color = 'Gray') {
    Write-Host ($pad + $msg) -ForegroundColor $color
    if ($color -eq 'Red') { Write-Log 'ERROR' $msg } elseif ($color -eq 'Yellow') { Write-Log 'WARN' $msg }
}

function Copy-Tree([string]$from, [string]$to, [string[]]$skipDirs = @()) {
    $rc = @($from, $to, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($skipDirs.Count -gt 0) { $rc += '/XD'; $rc += $skipDirs }
    & robocopy.exe @rc | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Could not copy $from [robocopy code $LASTEXITCODE]" }
}

function Get-FolderSize([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0L }
    $sum = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return [long]$sum
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N1} GB' -f ($bytes / 1GB)) }
    return ('{0:N1} MB' -f ($bytes / 1MB))
}

# Empties each folder but keeps the folder itself; returns bytes freed and bytes that were in use
function Clear-CacheFolders([string[]]$folders) {
    $before = 0L
    foreach ($f in $folders) { $before += Get-FolderSize $f }
    foreach ($f in $folders) {
        if (Test-Path -LiteralPath $f) {
            Get-ChildItem -LiteralPath $f -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $after = 0L
    foreach ($f in $folders) { $after += Get-FolderSize $f }
    return [pscustomobject]@{ Freed = $before - $after; Left = $after }
}

# Runs a command-line tool and prints its output in Swarlex's layout: indented, ANSI codes removed,
# "success / info / warn / error" tags coloured. The output goes to files rather than a pipe: tools such as
# spicetify start Spotify, which would inherit a pipe and keep it open, so reading it could never finish.
# True when version $a is newer than version $b ("1.2.10" vs "1.2.9"); anything unparsable is "not newer"
function Get-LatestRelease([string]$repo, [switch]$Full, [int]$TimeoutSec = 15) {
    # The GitHub API allows only 60 calls an hour per internet address, so it is used only when the
    # release notes and file list are needed. The version alone comes from the /releases/latest
    # redirect of the normal website, and when the API is out of calls the file list comes from the
    # website as well (without release notes).
    $ua = 'Swarlex-Manager'
    function Get-WebTag {
        # A renamed or moved repository answers with a redirect to its new name first; follow it and
        # remember the new name, since the download links below are built from it.
        $url = 'https://github.com/' + $script:webRepo + '/releases/latest'
        for ($hop = 0; $hop -lt 4; $hop++) {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = $ua; $req.Timeout = $TimeoutSec * 1000
            $res = $req.GetResponse()
            try { $loc = [string]$res.Headers['Location'] } finally { $res.Close() }
            if (-not $loc) { break }
            $loc = ([Uri]::new([Uri]$url, $loc)).AbsoluteUri
            if ($loc -match '^https://github\.com/([^/]+/[^/]+)/releases/tag/([^/?#]+)$') {
                $script:webRepo = $Matches[1]
                return [Uri]::UnescapeDataString($Matches[2])
            }
            if ($loc -notmatch '^https://github\.com/[^/]+/[^/]+/releases/latest$') { break }
            $url = $loc
        }
        throw 'GitHub did not report a latest release'
    }
    $script:webRepo = $repo
    if (-not $Full) {
        try { return [pscustomobject]@{ tag_name = (Get-WebTag); body = ''; assets = @() } } catch { }
    }
    try {
        return Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = $ua } -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest')
    } catch {
        if (-not $Full) { throw }
        $apiError = $_
    }
    try {
        $tag = Get-WebTag
        $html = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -UserAgent $ua -Uri ('https://github.com/' + $script:webRepo + '/releases/expanded_assets/' + $tag)).Content
        $prefix = '/' + $script:webRepo + '/releases/download/' + $tag + '/'
        $assets = @([regex]::Matches($html, 'href="(' + [regex]::Escape($prefix) + '[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique |
            ForEach-Object { [pscustomobject]@{ name = [Uri]::UnescapeDataString($_.Substring($prefix.Length)); browser_download_url = 'https://github.com' + $_ } })
        return [pscustomobject]@{ tag_name = $tag; body = ''; assets = $assets }
    } catch { throw $apiError }
}
function Test-NewerVersion([string]$a, [string]$b) {
    try { return ([version]($a.Trim().TrimStart('v')) -gt [version]($b.Trim().TrimStart('v'))) } catch { return $false }
}

function Write-ToolLine([string]$l) {
    $l = ($l -replace '\x1b\[[0-9;?]*[A-Za-z]', '').TrimEnd()
    if (-not $l.Trim()) { return }
    # winget's licence boilerplate, repeated on every install
    if ($l -match 'licensed to you by its owner|not responsible for, nor does it grant any licenses|^\s*Microsoft is not responsible') { return }
    # Web addresses shrink to their file name and nothing wraps back to the left edge of the window
    $l = [regex]::Replace($l, 'https?://\S+', { param($m) @($m.Value -split '[/?#]' | Where-Object { $_ })[-1] })
    $max = 70
    try { $max = [Math]::Max(50, [Console]::WindowWidth - $pad.Length - 3) } catch { }
    if ($l.Trim().Length -gt $max) { $l = $l.Trim().Substring(0, $max - 1) + '~' }
    $m = [regex]::Match($l, '^\s*(success|info|warn|warning|error|fatal)\s+(.*)$', 'IgnoreCase')
    if ($m.Success) {
        $tag = $m.Groups[1].Value.ToLower()
        $color = @{ success = 'Green'; info = 'Cyan'; warn = 'Yellow'; warning = 'Yellow'; error = 'Red'; fatal = 'Red' }[$tag]
        Write-Host ($pad + '  ' + $tag.PadRight(8)) -ForegroundColor $color -NoNewline
        Write-Host $m.Groups[2].Value -ForegroundColor Gray
        if ($color -eq 'Red') { Write-Log 'ERROR' ('tool: ' + $m.Groups[2].Value) }
    } else {
        Write-Host ($pad + '  ' + $l.Trim()) -ForegroundColor DarkGray
    }
}
# A terminal redraws progress bars and spinners in place; in a captured file every redraw is its own
# line. Keep what the screen would finally show: the last redraw of each line, no spinner frames
# ("- Extracting", "\ Extracting"...), one line per run of progress frames, no bar blocks.
function Get-ToolLines([string]$raw) {
    $out = New-Object System.Collections.Generic.List[string]
    $lastKey = $null
    foreach ($seg in ($raw -split "`n")) {
        $line = @($seg -split "`r" | Where-Object { $_.Trim() })
        if ($line.Count -eq 0) { continue }
        $l = ($line[-1] -replace '\x1b\[[0-9;?]*[A-Za-z]', '')
        $l = ($l -replace '[\u2580-\u259F\u25A0\u25AC]+', ' ' -replace '\s{2,}', ' ').Trim()
        if (-not $l) { continue }
        if ($l -match '^[-\\|/]\s') { continue }
        # Lines that differ only in numbers are frames of one progress line: keep the newest
        $key = $l -replace '\d+', '#'
        if ($key -eq $lastKey -and $l -match '\d') { $out[$out.Count - 1] = $l } else { $out.Add($l) }
        $lastKey = $key
    }
    return ,$out
}

function Invoke-Tool([string]$exe, [string]$argLine) {
    # Only real programs: npm and pnpm also install a .ps1 shim that PowerShell would pick first,
    # and a script cannot be started as a process ("not a valid Win32 application").
    $cmd = @(Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(exe|cmd|bat|com)$' })[0]
    if (-not $cmd) { Say ('[x] ' + $exe + ' was not found.') 'Red'; return 9009 }
    # Output files of earlier runs that a still-running Spotify kept open can go now
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'swarlex-tool-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $id = [guid]::NewGuid().ToString('N')
    $out = Join-Path $env:TEMP ('swarlex-tool-' + $id + '.out')
    $err = Join-Path $env:TEMP ('swarlex-tool-' + $id + '.err')
    try {
        $p = Start-Process -FilePath $cmd.Source -ArgumentList $argLine -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        $null = $p.Handle
        # The process only - not the Spotify it may have started. Its output is shown once it is done,
        # so meanwhile a spinner and the elapsed time show that it is still working.
        $live = $true
        try { $live = -not [Console]::IsOutputRedirected } catch { $live = $false }
        $frames = [char[]]@(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $i = 0
        while (-not $p.WaitForExit(150)) {
            if ($live -and $sw.ElapsedMilliseconds -gt 1200) {
                Write-Host ("`r" + $pad + '  ' + $frames[$i % $frames.Count] + ' working... ' + [int]$sw.Elapsed.TotalSeconds + 's   ') -ForegroundColor DarkGray -NoNewline
                $i++
            }
        }
        if ($live -and $sw.ElapsedMilliseconds -gt 1200) { Write-Host ("`r" + (' ' * ($pad.Length + 24)) + "`r") -NoNewline }
        foreach ($file in $out, $err) {
            if (-not (Test-Path -LiteralPath $file)) { continue }
            # A child it started can still hold the file open for writing, so it is read with sharing on
            $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite, Delete')
            $sr = New-Object IO.StreamReader($fs)
            try { $raw = $sr.ReadToEnd() } finally { $sr.Close() }
            foreach ($l in (Get-ToolLines $raw)) { Write-ToolLine $l }
        }
        return $p.ExitCode
    } finally {
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    }
}

# Appends to %APPDATA%\Swarlex Manager\history.log (same format as the batch :LOG); the size is
# kept in check at startup by HISTORYTRIM. History must never break the action it records.
function Write-History([string]$action, [string]$result) {
    Write-Log 'ACTION' ($action + ': ' + $result)
    try {
        $dir = $env:SWX_DATA
        if (-not $dir) { $dir = Join-Path $env:APPDATA 'Swarlex Manager' }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $line = '{0}  {1,-16} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $action, $result
        [IO.File]::AppendAllText((Join-Path $dir 'history.log'), $line + "`r`n", (New-Object Text.UTF8Encoding $false))
    } catch { }
}
::SWX_PS_END

::SWX_PS_BEGIN SELFUPDATE
# SWX_SU_MODE:
#   check    compare this file's version with the latest GitHub release and show what changed.
#            Exit 0 = a newer version exists, 10 = this is the latest, 1 = could not check.
#   auto     used at start with Auto-Update on: silent unless a newer version exists, which is then
#            installed like "install". Exit 0 = installed, 10 = nothing to do, 11 = GitHub unreachable.
#   install  download that release's Swarlex-Manager.bat, check its SHA-256 against the release's
#            .sha256 file and that it really is Swarlex at that version, then write a helper that swaps
#            the file once this window is closed (the old copy is kept as Swarlex-Manager.previous.bat).
# SWX_TEST_RELEASE (a JSON file shaped like GitHub's release) replaces the online lookup in tests.
$repo = $env:SWX_REPO
$cur = $env:SWX_VERSION
$work = Join-Path $env:TEMP 'swarlex-update'
$helper = Join-Path $env:TEMP 'swarlex-selfupdate-run.cmd'
try {
    if ($env:SWX_TEST_RELEASE) { $rel = Get-Content -LiteralPath $env:SWX_TEST_RELEASE -Raw | ConvertFrom-Json }
    elseif ($env:SWX_SU_MODE -eq 'auto') {
        # the version alone is a quick, unlimited lookup; the file list is only fetched when it is needed
        $rel = Get-LatestRelease $repo -TimeoutSec 6
        if (Test-NewerVersion ([string]$rel.tag_name) $cur) { $rel = Get-LatestRelease $repo -Full -TimeoutSec 20 }
    }
    else { $rel = Get-LatestRelease $repo -Full }
} catch {
    if ($env:SWX_SU_MODE -eq 'auto') { exit 11 }
    Say ('[x] Could not reach GitHub: ' + $_.Exception.Message) 'Red'
    exit 1
}
$latest = ([string]$rel.tag_name).TrimStart('v')
if (-not (Test-NewerVersion $latest $cur)) {
    if ($env:SWX_SU_MODE -eq 'auto') { exit 10 }
    Say ('[+] Swarlex v' + $cur + ' is the latest version.') 'Green'
    exit 10
}
if ($env:SWX_SU_MODE -eq 'auto') {
    Clear-Host
    Write-Host ''; Write-Host ''
    Say ('[*] Updating Swarlex v' + $cur + ' to v' + $latest + '...') 'Cyan'
    Write-Host ''
}

if ($env:SWX_SU_MODE -eq 'check') {
    Say ('[*] Swarlex v' + $latest + ' is available - you have v' + $cur + '.') 'Cyan'
    $notes = @(([string]$rel.body) -split "`r?`n" |
        Where-Object { $_ -notmatch 'SHA-256' } |
        ForEach-Object { ($_ -replace '^[\s#>*-]+', '' -replace '\*\*|`', '').Trim() } | Where-Object { $_ } | Select-Object -First 10)
    if ($notes.Count) {
        Write-Host ''
        Write-Host ($pad + "What's new:") -ForegroundColor White
        foreach ($n in $notes) { Write-ToolLine $n }
    }
    exit 0
}

try {
    $batAsset = @($rel.assets | Where-Object { $_.name -eq 'Swarlex-Manager.bat' })[0]
    $shaAsset = @($rel.assets | Where-Object { $_.name -eq 'Swarlex-Manager.bat.sha256' })[0]
    if (-not $batAsset -or -not $shaAsset) { throw 'the release has no Swarlex-Manager.bat and .sha256 to download' }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work | Out-Null
    $newFile = Join-Path $work 'Swarlex-Manager.bat'
    $shaFile = Join-Path $work 'Swarlex-Manager.bat.sha256'
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'Swarlex-Manager')
    $wc.DownloadFile([string]$batAsset.browser_download_url, $newFile)
    $wc.DownloadFile([string]$shaAsset.browser_download_url, $shaFile)
    $expected = (([IO.File]::ReadAllText($shaFile)).Trim() -split '\s+')[0]
    $actual = (Get-FileHash -LiteralPath $newFile -Algorithm SHA256).Hash
    if (-not $expected -or $actual -ne $expected) { throw 'the download is corrupted - its SHA-256 does not match the release' }
    $text = [IO.File]::ReadAllText($newFile)
    if ($text -notmatch '::SWX_PS_BEGIN COMMON' -or $text -notmatch ('(?m)^set "SWX_VERSION=' + [regex]::Escape($latest) + '"')) {
        throw ('the downloaded file is not Swarlex Manager v' + $latest)
    }
    $previous = Join-Path $env:SWX_DATA 'Swarlex-Manager.previous.bat'
    $lines = @(
        '@echo off',
        'chcp 65001 >nul',
        'title Swarlex - installing update',
        'rem Waits for the old Swarlex window to close, swaps the file, starts the new version.',
        'ping -n 3 127.0.0.1 >nul',
        ('copy /y "' + $env:SWX_SELF + '" "' + $previous + '" >nul 2>&1'),
        'set "N=0"',
        ':retry',
        ('copy /y "' + $newFile + '" "' + $env:SWX_SELF + '" >nul 2>&1 && goto done'),
        'set /a N+=1',
        'if %N% lss 15 (ping -n 2 127.0.0.1 >nul & goto retry)',
        ('echo Could not replace "' + $env:SWX_SELF + '".'),
        ('echo The new version is here: "' + $newFile + '"'),
        'pause',
        'exit /b 1',
        ':done',
        ('start "" cmd /d /c ""' + $env:SWX_SELF + '""'),
        '(goto) 2>nul & del "%~f0"'
    )
    [IO.File]::WriteAllText($helper, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))
    Say ('[+] v' + $latest + ' downloaded and verified - Swarlex restarts with it in a moment.') 'Green'
    Say '    The old version is kept in %APPDATA%\Swarlex Manager.' 'DarkGray'
    Write-History 'Swarlex update' ('v' + $cur + ' -> v' + $latest)
    # The new version starts with a clean slate instead of announcing the update it just installed
    if ($env:SWX_UPDATE_FILE) { Remove-Item -LiteralPath $env:SWX_UPDATE_FILE -Force -ErrorAction SilentlyContinue }
    exit 0
} catch {
    Say ('[x] Update failed: ' + $_.Exception.Message) 'Red'
    Write-History 'Swarlex update' ('failed - ' + $_.Exception.Message)
    exit 1
}
::SWX_PS_END

::SWX_PS_BEGIN TOOLRUN
# Batch side: SWX_TOOL_EXE + SWX_TOOL_ARGS (one command line, quotes kept). Exit code = the tool's.
exit (Invoke-Tool $env:SWX_TOOL_EXE $env:SWX_TOOL_ARGS)
::SWX_PS_END

::SWX_PS_BEGIN HISTORYTRIM
$file = Join-Path $env:SWX_DATA 'history.log'
$keep = @(Get-Content -LiteralPath $file -Encoding UTF8 | Select-Object -Last 500)
Set-Content -LiteralPath $file -Value $keep -Encoding UTF8
exit 0
::SWX_PS_END

::SWX_PS_BEGIN HISTORYVIEW
$file = Join-Path $env:SWX_DATA 'history.log'
$lines = @()
if (Test-Path -LiteralPath $file) { $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -Last 20) }
if ($lines.Count -eq 0) {
    Say 'No actions recorded yet.' 'DarkGray'
} else {
    [array]::Reverse($lines)
    foreach ($l in $lines) {
        if ($l.Length -gt 62) { $l = $l.Substring(0, 61) + '~' }
        $when = if ($l.Length -ge 16) { $l.Substring(0, 16) } else { $l }
        $what = if ($l.Length -gt 18) { $l.Substring(18) } else { '' }
        Write-Host ($pad + $when + '  ') -ForegroundColor DarkGray -NoNewline
        Write-Host $what -ForegroundColor $(if ($what -match 'failed') { 'Red' } else { 'White' })
    }
    Write-Host ''
    Say ('Newest first. Full log: ' + $file) 'DarkGray'
}
exit 0
::SWX_PS_END

::SWX_PS_BEGIN PATCHER
# Writes the same app.asar stub the official Vencord installer uses, pointing at this build's dist.
# Vencord screens print result lines flush with the indent, so no extra 2-space offset here.
$pad = ' ' * [int]$env:SWX_PAD
$mode = $env:SWX_MODE
$patcher = Join-Path $env:SWX_VENCORD_DIR 'dist\patcher.js'

function New-VencordAsar([string]$target) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $index = $utf8.GetBytes('require(' + (ConvertTo-Json -Compress $target) + ')')
    $pkg = $utf8.GetBytes('{' + "`n`t" + '"name": "discord",' + "`n`t" + '"main": "index.js"' + "`n" + '}')
    $json = $utf8.GetBytes('{"files":{"index.js":{"size":' + $index.Length + ',"offset":"0"},"package.json":{"size":' + $pkg.Length + ',"offset":"' + $index.Length + '"}}}')
    $align = (4 - ($json.Length % 4)) % 4
    $payload = 4 + $json.Length + $align
    $ms = New-Object System.IO.MemoryStream
    foreach ($n in @(4, (4 + $payload), $payload, $json.Length)) { $ms.Write([BitConverter]::GetBytes([uint32]$n), 0, 4) }
    $ms.Write($json, 0, $json.Length)
    $ms.Write([byte[]](@(48) * 4), 0, $align)
    $ms.Write($index, 0, $index.Length)
    $ms.Write($pkg, 0, $pkg.Length)
    return ,$ms.ToArray()
}

if ($mode -eq 'install' -and -not (Test-Path -LiteralPath $patcher)) {
    Say "[x] Build output missing: $patcher" 'Red'
    exit 3
}

$installs = @()
foreach ($name in 'Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment') {
    $root = Join-Path $env:LOCALAPPDATA $name
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $app = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources') } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($app) { $installs += [pscustomobject]@{ Name = $name; Resources = (Join-Path $app.FullName 'resources') } }
}
# "all", one build, or a comma list of builds (Repair fixes only the broken ones)
$target = $env:SWX_TARGET_DISCORD
if (-not $target) {
    # Never guess: an empty target used to mean "all", which could patch or unpatch builds nobody chose
    Say '[x] No Discord build was selected.' 'Red'
    exit 2
}
if ($target -ne 'all') {
    $want = @($target -split '[,\s]+' | Where-Object { $_ })
    $installs = @($installs | Where-Object { $want -contains $_.Name })
}
if ($installs.Count -eq 0) {
    Say '[x] No Discord desktop installation was found.' 'Red'
    exit 2
}

$failed = 0
foreach ($d in $installs) {
    $asar = Join-Path $d.Resources 'app.asar'
    $orig = Join-Path $d.Resources '_app.asar'
    try {
        if ($mode -eq 'install') {
            $current = Get-Item -LiteralPath $asar -ErrorAction SilentlyContinue
            $isStub = $current -and ($current.PSIsContainer -or $current.Length -lt 64KB)
            if (-not (Test-Path -LiteralPath $orig)) {
                if (-not $current) { throw 'app.asar is missing - reinstall Discord.' }
                if ($isStub) { throw 'app.asar looks modified but _app.asar is missing - reinstall Discord.' }
                Move-Item -LiteralPath $asar -Destination $orig
            } elseif ($current) {
                if ($isStub) {
                    Remove-Item -LiteralPath $asar -Recurse -Force
                } else {
                    Remove-Item -LiteralPath $orig -Force
                    Move-Item -LiteralPath $asar -Destination $orig
                }
            }
            [IO.File]::WriteAllBytes($asar, (New-VencordAsar $patcher))
            Say "[+] $($d.Name): patched" 'Green'
            Write-Log 'INFO' "Patched $($d.Resources)"
        } else {
            if (-not (Test-Path -LiteralPath $orig)) { Say "[-] $($d.Name): not patched" 'DarkGray'; continue }
            if (Test-Path -LiteralPath $asar) { Remove-Item -LiteralPath $asar -Recurse -Force }
            Move-Item -LiteralPath $orig -Destination $asar
            Say "[+] $($d.Name): restored" 'Green'
            Write-Log 'INFO' "Restored the original app.asar in $($d.Resources)"
        }
    } catch {
        Say "[x] $($d.Name): $($_.Exception.Message)" 'Red'
        $failed++
    }
}
if ($failed -gt 0) { exit 1 }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN DOCTOR
# Finds userplugins that break the Vencord build and parks them in userplugins\.disabled
# (Vencord ignores folders starting with a dot).
$pad = ' ' * [int]$env:SWX_PAD
$dir = $env:SWX_VENCORD_DIR
$up = Join-Path $dir 'src\userplugins'
$hold = Join-Path $up '.swarlex-testing'
$off = Join-Path $up '.disabled'
# Same log as :BUILD_VENCORD, so the excerpt shown after a failed check comes from the last build
$log = if ($env:SWX_BUILD_LOG) { $env:SWX_BUILD_LOG } else { Join-Path $env:TEMP 'swarlex-build.log' }
$dist = Join-Path $dir 'dist'
$distBackup = Join-Path $env:TEMP 'swarlex-vencord-dist'

function Restore-Held {
    if (-not (Test-Path -LiteralPath $hold)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $hold -Force)) {
        $target = Join-Path $up $item.Name
        if (Test-Path -LiteralPath $target) { Say "[!] Duplicate left in .swarlex-testing: $($item.Name)" 'Yellow' }
        else { Move-Item -LiteralPath $item.FullName -Destination $target }
    }
    if (@(Get-ChildItem -LiteralPath $hold -Force).Count -eq 0) { Remove-Item -LiteralPath $hold -Force }
}

if ($env:SWX_DOCTOR_MODE -eq 'recover') {
    Restore-Held
    exit 0
}

function Test-Build {
    $cmdline = 'cd /d "' + $dir + '" && node --require=./scripts/suppressExperimentalWarnings.js scripts/build/build.mjs > "' + $log + '" 2>&1'
    & cmd.exe /d /s /c ('"' + $cmdline + '"') | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Set-Enabled([string[]]$enabled) {
    if (-not (Test-Path -LiteralPath $hold)) { New-Item -ItemType Directory -Path $hold | Out-Null }
    foreach ($name in $all) {
        $inUp = Join-Path $up $name
        $inHold = Join-Path $hold $name
        if ($enabled -contains $name) {
            if (Test-Path -LiteralPath $inHold) { Move-Item -LiteralPath $inHold -Destination $inUp }
        } elseif (Test-Path -LiteralPath $inUp) {
            Move-Item -LiteralPath $inUp -Destination $inHold
        }
    }
}

function Find-Culprits([string[]]$base, [string[]]$cands) {
    Say ('    testing ' + $cands.Count + ' plugin(s)...') 'DarkGray'
    Set-Enabled ($base + $cands)
    if (Test-Build) { return @() }
    if ($cands.Count -eq 1) { return @($cands[0]) }
    $mid = [int][math]::Floor($cands.Count / 2)
    $first = @($cands[0..($mid - 1)])
    $second = @($cands[$mid..($cands.Count - 1)])
    $bad1 = @(Find-Culprits $base $first)
    $good1 = @($first | Where-Object { $bad1 -notcontains $_ })
    $bad2 = @(Find-Culprits ($base + $good1) $second)
    return @($bad1 + $bad2)
}

$all = @(Get-ChildItem -LiteralPath $up -Force | Where-Object { -not ($_.Name.StartsWith('.') -or $_.Name.StartsWith('_')) } | ForEach-Object { $_.Name })
if ($all.Count -eq 0) { exit 1 }

Say ('[*] Build still failing - checking your ' + $all.Count + ' userplugins for the broken one...') 'Cyan'
$bad = @()
$outcome = 'unknown'
try {
    if (Test-Path -LiteralPath $distBackup) { Remove-Item -LiteralPath $distBackup -Recurse -Force }
    if (Test-Path -LiteralPath $dist) { Copy-Tree $dist $distBackup }

    if (Test-Build) {
        $outcome = 'passed'
    } else {
        $logText = [IO.File]::ReadAllText($log)
        $hints = @([regex]::Matches($logText, 'userplugins[\\/]+([^\\/:"''\s]+)') |
            ForEach-Object { $h = $_.Groups[1].Value; $all | Where-Object { $_ -eq $h } } |
            Select-Object -Unique)
        Set-Enabled @()
        if (-not (Test-Build)) {
            $outcome = 'core'
        } else {
            $solved = $false
            if ($hints.Count -gt 0) {
                $base = @($all | Where-Object { $hints -notcontains $_ })
                Say ('    testing without: ' + ($hints -join ', ')) 'DarkGray'
                Set-Enabled $base
                if (Test-Build) {
                    foreach ($name in $hints) {
                        Set-Enabled ($base + $name)
                        if (Test-Build) { $base += $name } else { $bad += $name }
                    }
                    $solved = $true
                }
            }
            if (-not $solved) { $bad = @(Find-Culprits @() $all) }
            if ($bad.Count -gt 0) {
                Set-Enabled @($all | Where-Object { $bad -notcontains $_ })
                if (Test-Build) { $outcome = 'found' } else { $bad = @() }
            }
        }
    }
} catch {
    Say ('[x] Plugin check failed: ' + $_.Exception.Message) 'Red'
    $outcome = 'error'
    $bad = @()
}

try {
    Set-Enabled @($all | Where-Object { $bad -notcontains $_ })
    if ($outcome -eq 'found') {
        if (-not (Test-Path -LiteralPath $off)) { New-Item -ItemType Directory -Path $off | Out-Null }
        foreach ($name in $bad) {
            $dest = Join-Path $off $name
            $n = 2
            while (Test-Path -LiteralPath $dest) { $dest = Join-Path $off ($name + '-' + $n); $n++ }
            Move-Item -LiteralPath (Join-Path $hold $name) -Destination $dest
        }
    }
    Restore-Held
    if ($outcome -ne 'found' -and $outcome -ne 'passed' -and (Test-Path -LiteralPath $distBackup)) {
        & robocopy.exe $distBackup $dist /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    }
    if (Test-Path -LiteralPath $distBackup) { Remove-Item -LiteralPath $distBackup -Recurse -Force }
} catch {
    Say ('[x] Could not put plugin folders back: ' + $_.Exception.Message) 'Red'
    Say ('    Check ' + $hold) 'Yellow'
    exit 1
}

switch ($outcome) {
    'passed' {
        Say '[+] Build passed on retry.' 'Green'
        exit 0
    }
    'found' {
        Say ('[!] Disabled ' + $bad.Count + ' broken userplugin(s): ' + ($bad -join ', ')) 'Yellow'
        Write-History 'Plugin check' ('turned off broken: ' + ($bad -join ', '))
        Say ('    Moved to ' + $off) 'DarkGray'
        Say '    Turn it back on in Plugin Hub > [2] Manage Plugins.' 'DarkGray'
        exit 0
    }
    'core' {
        Say '[x] Vencord itself fails to build, even without userplugins.' 'Red'
        Say '    Try [2] Update Vencord. Your plugins were not changed.' 'Yellow'
        exit 1
    }
    default {
        Say '[x] No single plugin to blame - none of them were changed.' 'Red'
        exit 1
    }
}
::SWX_PS_END

::SWX_PS_BEGIN SPICEUPDATE
# Exit codes: 0 updated, 10 already up to date, 2 could not check, 1 failed.
# "spicetify upgrade" exits 0 even when it cannot reach GitHub, so the version is compared before and after.
$flags = @(($env:SPICETIFY_FLAGS -split ' ') | Where-Object { $_ })
function Get-SpicetifyVersion {
    try { return "$(@(& spicetify -v) | Select-Object -Last 1)".Trim() } catch { return '' }
}
$current = Get-SpicetifyVersion
if (-not $current) { Say '[x] Could not read the installed Spicetify version.' 'Red'; exit 1 }
try {
    $release = Get-LatestRelease 'spicetify/cli'
    $latest = ([string]$release.tag_name).TrimStart('v')
} catch {
    Say ('[x] Could not check for updates: ' + $_.Exception.Message) 'Red'
    Write-History 'Update Spicetify' 'failed - could not check for updates'
    exit 2
}
Say ('[*] Installed: ' + $current + '   Latest: ' + $latest) 'Cyan'
if ($current -eq $latest) {
    Say '[+] Spicetify is already up to date.' 'Green'
    Write-History 'Update Spicetify' "already up to date [$current]"
    exit 10
}

$null = Invoke-Tool 'spicetify' ((@('upgrade') + $flags) -join ' ')
$now = Get-SpicetifyVersion
if ($now -ne $latest) {
    Say '[x] Spicetify could not be updated - see the output above.' 'Red'
    Write-History 'Update Spicetify' 'failed'
    exit 1
}
Say ('[+] Spicetify updated: ' + $current + ' -> ' + $latest) 'Green'
Write-History 'Update Spicetify' ($current + ' -> ' + $latest)

# The re-apply that "spicetify upgrade" runs is a child process without --bypass-admin, so it fails as admin
if ($flags -contains '--bypass-admin') {
    Say '[*] Re-applying Spicetify to Spotify...' 'Cyan'
    $rc = Invoke-Tool 'spicetify' ((@('restore', 'backup', 'apply') + $flags) -join ' ')
    if ($rc -ne 0) { $rc = Invoke-Tool 'spicetify' ((@('backup', 'apply') + $flags) -join ' ') }
    if ($rc -ne 0) {
        Say '[x] Updated, but re-applying failed. Use [1] Apply Spicetify.' 'Red'
        exit 1
    }
}
exit 0
::SWX_PS_END

::SWX_PS_BEGIN UPDATECHECK
# Background job started by :START_UPDATE_CHECK. Writes "vencord=1" and/or "spicetify=<version>"
# to SWX_UPDATE_FILE; the file only appears once both checks are done.
$ErrorActionPreference = 'Continue'
$env:GIT_TERMINAL_PROMPT = '0'
$found = @()
try {
    $dir = $env:SWX_VENCORD_DIR
    if ($dir -and (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        $local = "$(& git -C $dir rev-parse HEAD 2>$null)".Trim()
        $remote = ("$(& git -C $dir ls-remote origin HEAD 2>$null)".Trim() -split '\s+')[0]
        if ($local -and $remote -and $local -ne $remote) { $found += 'vencord=1' }
    }
} catch { }
try {
    if (Get-Command spicetify -ErrorAction SilentlyContinue) {
        $current = "$(@(& spicetify -v 2>$null) | Select-Object -Last 1)".Trim()
        $release = Get-LatestRelease 'spicetify/cli'
        $latest = ([string]$release.tag_name).TrimStart('v')
        if ($current -and $latest -and $current -ne $latest) { $found += "spicetify=$latest" }
    }
} catch { }
try {
    # millver = installed version for the dashboard; millennium = a newer release exists
    $loader = Join-Path ([string]$env:SWX_STEAM_DIR) 'wsock32.dll'
    if ($env:SWX_STEAM_DIR -and (Test-Path -LiteralPath $loader)) {
        $vi = (Get-Item -LiteralPath $loader).VersionInfo
        if ($vi.ProductName -match 'Millennium') {
            $cur = ([string]$vi.ProductVersion).Trim().TrimStart('v')
            if ($cur) { $found += "millver=$cur" }
            $rel = Get-LatestRelease 'SteamClientHomebrew/Millennium'
            $latest = ([string]$rel.tag_name).TrimStart('v')
            if ($cur -and $latest -and $cur -ne $latest) { $found += "millennium=$latest" }
        }
    }
} catch { }
try {
    # swarlex = a newer Swarlex Manager release on GitHub
    if ($env:SWX_REPO -and $env:SWX_VERSION) {
        $rel = Get-LatestRelease $env:SWX_REPO
        $latest = ([string]$rel.tag_name).TrimStart('v')
        if (Test-NewerVersion $latest $env:SWX_VERSION) { $found += "swarlex=$latest" }
    }
} catch { }
$tmp = $env:SWX_UPDATE_FILE + '.tmp'
[IO.File]::WriteAllLines($tmp, [string[]]$found)
Move-Item -LiteralPath $tmp -Destination $env:SWX_UPDATE_FILE -Force
exit 0
::SWX_PS_END

::SWX_PS_BEGIN BUILDLOG
# Prints the useful part of a quiet build/install log under the error line that precedes it.
$pad = ' ' * ([int]$env:SWX_PAD + 4)
$log = $env:SWX_LOG
$lines = @()
if ($log -and (Test-Path -LiteralPath $log)) {
    $lines = @([IO.File]::ReadAllLines($log) |
        ForEach-Object { ($_ -replace '\x1b\[[0-9;]*[A-Za-z]', '') -replace '[^\x09\x20-\x7E]', '' } |
        Where-Object { $_.Trim() })
}
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\[ERROR\]|ERR_|ERR!|Error:|error TS\d+') { $start = $i; break }
}
$show = if ($start -ge 0) { @($lines[$start..([Math]::Min($lines.Count - 1, $start + 14))]) } else { @($lines | Select-Object -Last 15) }
if ($show.Count -gt 0) { $show[0] = $show[0].TrimStart() }
foreach ($l in $show) { Write-Host ($pad + $l.TrimEnd()) -ForegroundColor DarkGray }
Write-Host ($pad + 'Full log: ' + $log) -ForegroundColor DarkGray
foreach ($l in $show) { Write-Log 'ERROR' ('  | ' + $l.Trim()) }
Write-Log 'ERROR' ('  full output: ' + $log)
exit 0
::SWX_PS_END

::SWX_PS_BEGIN PLUGININSTALL
# Installs a userplugin from a link. GitHub repo links are cloned with git (zip download if git fails);
# links to a folder inside a repo (.../tree/<branch>/<path>) are downloaded as a zip and only that folder is kept.
$env:GIT_TERMINAL_PROMPT = '0'
$up = Join-Path $env:SWX_VENCORD_DIR 'src\userplugins'
$off = Join-Path $up '.disabled'
$url = ([string]$env:SWX_PLUGIN_URL).Trim()
if (-not (Test-Path -LiteralPath (Join-Path $env:SWX_VENCORD_DIR 'src'))) { Say '[x] Vencord source folder not found.' 'Red'; exit 1 }

# Single-file plugin (.../blob/<branch>/<path>/plugin.tsx): Vencord loads these directly from userplugins
$blob = [regex]::Match($url, '^(?:https?://)?(?:www\.)?github\.com/([^/\s]+)/([^/\s]+)/blob/([^/\s]+)/(\S+?\.(?:ts|tsx|js|jsx))(?:[#?]\S*)?$')
if ($blob.Success) {
    $file = ($blob.Groups[4].Value -split '/')[-1]
    $target = Join-Path $up $file
    if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath (Join-Path $off $file))) { Say "[x] A plugin named '$file' is already installed." 'Red'; exit 1 }
    New-Item -ItemType Directory -Path $up -Force | Out-Null
    Say "[*] Downloading $file..." 'Cyan'
    try {
        $raw = 'https://raw.githubusercontent.com/' + $blob.Groups[1].Value + '/' + $blob.Groups[2].Value + '/' + $blob.Groups[3].Value + '/' + $blob.Groups[4].Value
        Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $target
    } catch {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        Say ('[x] Download failed: ' + $_.Exception.Message) 'Red'
        exit 1
    }
    Say "[+] Installed $file" 'Green'
    Write-History 'Install plugin' "installed $file"
    Say '    Use [1] Patch Discord to build it into Discord.' 'DarkGray'
    exit 0
}

$gh = [regex]::Match($url, '^(?:https?://)?(?:www\.)?github\.com/([^/\s]+)/([^/\s#?]+?)(?:\.git)?(?:/tree/([^/\s]+)(?:/([^\s#?]+?))?)?/?(?:[#?]\S*)?$')
$sub = ''
$branch = ''
if ($gh.Success) {
    $owner = $gh.Groups[1].Value
    $repo = $gh.Groups[2].Value
    $branch = $gh.Groups[3].Value
    $sub = $gh.Groups[4].Value.Trim('/')
    $cloneUrl = "https://github.com/$owner/$repo.git"
    $name = if ($sub) { ($sub -split '/')[-1] } else { $repo }
} elseif ($url -match '^(https?://|git@)\S+$') {
    $cloneUrl = $url
    $name = ($url.TrimEnd('/') -split '[/:]')[-1] -replace '\.git$', ''
} else {
    Say '[x] Not a link. Example: https://github.com/user/plugin' 'Red'
    exit 1
}
if (-not $name -or $name.StartsWith('.') -or $name.StartsWith('_')) { Say '[x] Could not work out a plugin name from that link.' 'Red'; exit 1 }
$target = Join-Path $up $name
if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath (Join-Path $off $name))) {
    Say "[x] A plugin named '$name' is already installed." 'Red'
    exit 1
}
New-Item -ItemType Directory -Path $up -Force | Out-Null

$ok = $false
if (-not $sub) {
    Say "[*] Downloading $name with git..." 'Cyan'
    # GitHub links fall back to a zip download, so git's own errors would only be noise there
    $ErrorActionPreference = 'Continue'
    if ($gh.Success) { & git clone --depth 1 -q $cloneUrl $target 2>$null } else { & git clone --depth 1 -q $cloneUrl $target }
    $ok = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $target)
    $ErrorActionPreference = 'Stop'
    if (-not $ok -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Recurse -Force }
}
if (-not $ok -and $gh.Success) {
    $ref = if ($branch) { $branch } else { 'HEAD' }
    Say "[*] Downloading $name as a zip..." 'Cyan'
    $tmp = Join-Path $env:TEMP ('swarlex-plugin-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'plugin.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$owner/$repo/archive/$ref.zip" -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $root = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory)[0].FullName
        $src = if ($sub) { Join-Path $root ($sub -replace '/', '\') } else { $root }
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { throw "the folder '$sub' does not exist in that repository" }
        Copy-Tree $src $target
        $ok = $true
    } catch {
        Say ('[x] Download failed: ' + $_.Exception.Message) 'Red'
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
if (-not $ok) {
    if (-not $gh.Success) { Say '[x] git could not download that link.' 'Red' }
    exit 1
}

# Vencord imports every entry in userplugins, so a folder without an index file would break the build
function Test-PluginRoot([string]$p) {
    foreach ($n in 'index.ts', 'index.tsx', 'index.js', 'index.jsx') { if (Test-Path -LiteralPath (Join-Path $p $n)) { return $true } }
    return $false
}
if (-not (Test-PluginRoot $target)) {
    $cands = @(Get-ChildItem -LiteralPath $target -Directory -Recurse -Depth 1 -Force |
        Where-Object { $_.FullName -notmatch '\\(\.git|node_modules)(\\|$)' -and (Test-PluginRoot $_.FullName) })
    if ($cands.Count -eq 1) {
        $inner = Join-Path $env:TEMP ('swarlex-plugin-' + [guid]::NewGuid().ToString('N'))
        Copy-Tree $cands[0].FullName $inner
        Remove-Item -LiteralPath $target -Recurse -Force
        Copy-Tree $inner $target
        Remove-Item -LiteralPath $inner -Recurse -Force
        Say ('[*] Using the plugin folder inside the repository: ' + $cands[0].Name) 'Cyan'
    } else {
        Remove-Item -LiteralPath $target -Recurse -Force
        if ($cands.Count -gt 1) {
            Say ('[x] That repository contains several plugins: ' + (($cands | ForEach-Object { $_.Name }) -join ', ')) 'Red'
            Say '    Paste the link of one of them (.../tree/main/<folder>).' 'Yellow'
        } else {
            Say '[x] No Vencord plugin (index.ts/.tsx) found at that link.' 'Red'
        }
        exit 1
    }
}
Say "[+] Installed $name" 'Green'
Write-History 'Install plugin' "installed $name"
Say '    Use [1] Patch Discord to build it into Discord.' 'DarkGray'
exit 0
::SWX_PS_END

::SWX_PS_BEGIN MANAGE
# Interactive plugin list. Off = moved to userplugins\.disabled (Vencord skips dot folders);
# delete sends the plugin to the Recycle Bin so it can be recovered.
$ind = ' ' * [int]$env:SWX_PAD
$up = Join-Path $env:SWX_VENCORD_DIR 'src\userplugins'
$off = Join-Path $up '.disabled'
$width = 26
$line = ([string][char]0x2500) * 64
Add-Type -AssemblyName Microsoft.VisualBasic
$msg = $null
$msgColor = 'Gray'

function Get-Plugins {
    $items = @()
    if (Test-Path -LiteralPath $up) {
        $items += @(Get-ChildItem -LiteralPath $up -Force | Where-Object { -not ($_.Name.StartsWith('.') -or $_.Name.StartsWith('_')) } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; On = $true; Item = $_ } })
    }
    if (Test-Path -LiteralPath $off) {
        $items += @(Get-ChildItem -LiteralPath $off -Force | ForEach-Object { [pscustomobject]@{ Name = $_.Name; On = $false; Item = $_ } })
    }
    return ,@($items | Sort-Object Name)
}

function Show-Screen($plugins) {
    Clear-Host
    $bar = ([string][char]0x2500) * 62
    Write-Host ''
    Write-Host ''
    Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
    Write-Host ('MANAGE USERPLUGINS'.PadLeft(40).PadRight(62)) -ForegroundColor White -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Cyan
    Write-Host ''
    $onCount = @($plugins | Where-Object { $_.On }).Count
    Write-Host ($ind + '  ' + $onCount + ' on, ' + ($plugins.Count - $onCount) + ' off') -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''
    if ($plugins.Count -eq 0) { Write-Host ($ind + '  No userplugins installed.') -ForegroundColor DarkGray }
    $rows = [math]::Ceiling($plugins.Count / 2)
    for ($r = 0; $r -lt $rows; $r++) {
        Write-Host ($ind + '  ') -NoNewline
        foreach ($c in 0, 1) {
            $i = $r + $c * $rows
            if ($i -ge $plugins.Count) { break }
            $p = $plugins[$i]
            $label = $p.Name
            if ($label.Length -gt $width) { $label = $label.Substring(0, $width - 1) + '~' }
            $color = if ($p.On) { 'White' } else { 'DarkGray' }
            Write-Host (('{0,2}' -f ($i + 1)) + ' ') -ForegroundColor White -NoNewline
            Write-Host ([char]0x25CF) -ForegroundColor $(if ($p.On) { 'Green' } else { 'DarkGray' }) -NoNewline
            Write-Host (' ' + $label.PadRight($width + 1)) -ForegroundColor $color -NoNewline
        }
        Write-Host ''
    }
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    if ($msg) { Write-Host ($ind + '  ' + $msg) -ForegroundColor $msgColor }
    Write-Host ($ind + '  Number = turn on/off   del <number> = delete   Enter = back') -ForegroundColor DarkGray
    Write-Host ($ind + '  Changes take effect after [1] Patch Discord.') -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ($ind + '  ' + [char]0x203A) -ForegroundColor Cyan -NoNewline
    Write-Host ' Plugin: ' -ForegroundColor White -NoNewline
}

while ($true) {
    $plugins = Get-Plugins
    Show-Screen $plugins
    $in = [Console]::ReadLine()
    if ($null -eq $in) { break }
    $in = $in.Trim()
    if (-not $in -or $in -eq '0' -or $in -ieq 'b') { break }
    $m = [regex]::Match($in, '^(?i)(del(?:ete)?\s*)?(\d+)$')
    if (-not $m.Success) { $msg = 'Type a plugin number, or del <number>.'; $msgColor = 'Red'; continue }
    $n = [int]$m.Groups[2].Value
    if ($n -lt 1 -or $n -gt $plugins.Count) { $msg = "There is no plugin #$n."; $msgColor = 'Red'; continue }
    $p = $plugins[$n - 1]
    try {
        if ($m.Groups[1].Success) {
            Write-Host ($ind + '  Delete ' + $p.Name + '? It goes to the Recycle Bin. [Y/N]: ') -ForegroundColor Yellow -NoNewline
            $answer = [Console]::ReadLine()
            if ($answer -notmatch '^(?i)\s*y(es)?\s*$') { $msg = $p.Name + ' was not deleted.'; $msgColor = 'DarkGray'; continue }
            if ($p.Item.PSIsContainer) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p.Item.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p.Item.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
            $msg = '[+] ' + $p.Name + ' moved to the Recycle Bin.'
            Write-History 'Plugin' ('deleted ' + $p.Name)
            $msgColor = 'Green'
        } elseif ($p.On) {
            New-Item -ItemType Directory -Path $off -Force | Out-Null
            if (Test-Path -LiteralPath (Join-Path $off $p.Name)) { throw 'a turned-off copy with that name already exists' }
            Move-Item -LiteralPath $p.Item.FullName -Destination (Join-Path $off $p.Name)
            $msg = '[+] ' + $p.Name + ' turned off.'
            Write-History 'Plugin' ('turned off ' + $p.Name)
            $msgColor = 'Yellow'
        } else {
            if (Test-Path -LiteralPath (Join-Path $up $p.Name)) { throw 'an enabled plugin with that name already exists' }
            Move-Item -LiteralPath $p.Item.FullName -Destination (Join-Path $up $p.Name)
            $msg = '[+] ' + $p.Name + ' turned on.'
            Write-History 'Plugin' ('turned on ' + $p.Name)
            $msgColor = 'Green'
        }
    } catch {
        $msg = '[x] ' + $p.Name + ': ' + $_.Exception.Message
        $msgColor = 'Red'
    }
}
if ((Test-Path -LiteralPath $off) -and @(Get-ChildItem -LiteralPath $off -Force).Count -eq 0) { Remove-Item -LiteralPath $off -Force }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN SPOTCACHE
# Clears Spotify's cache and reports the space freed. Spotify\Storage is left alone: it is the
# default offline location, where downloaded songs live.
$base = Join-Path $env:LOCALAPPDATA 'Spotify'
$result = Clear-CacheFolders @((Join-Path $base 'Data'), (Join-Path $base 'Browser\Cache'))
Say ('[+] Spotify cache cleaned - freed ' + (Format-Size $result.Freed) + '. Downloaded songs were kept.') 'Green'
Write-History 'Spotify cache' ('freed ' + (Format-Size $result.Freed))
if ($result.Left -gt 0) { Say ('    ' + (Format-Size $result.Left) + ' could not be removed because Spotify still had it open.') 'DarkGray' }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN DISCACHE
# Clears the cache folders of every Discord build. Login (Local Storage), cookies (Network),
# IndexedDB and settings.json live in other folders and are not touched.
$pad = ' ' * [int]$env:SWX_PAD
$roots = @('discord', 'discordptb', 'discordcanary', 'discorddevelopment' |
    ForEach-Object { Join-Path $env:APPDATA $_ } |
    Where-Object { Test-Path -LiteralPath $_ })
if ($roots.Count -eq 0) { Say '[x] No Discord data folder was found.' 'Red'; exit 1 }
$folders = foreach ($r in $roots) {
    foreach ($n in 'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache') { Join-Path $r $n }
}
$result = Clear-CacheFolders @($folders)
Say ('[+] Discord cache cleaned - freed ' + (Format-Size $result.Freed) + '. Login and settings were kept.') 'Green'
Write-History 'Discord cache' ('freed ' + (Format-Size $result.Freed))
if ($result.Left -gt 0) { Say ('    ' + (Format-Size $result.Left) + ' could not be removed because Discord still had it open.') 'DarkGray' }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN MILLENNIUM
# SWX_MILL_MODE:
#   prepare   download the latest Windows release from GitHub, check its SHA-256 and that every .dll/.exe
#             is validly signed by Millennium's signer, unpack it to a staging folder. Steam may stay open.
#             Exit 0 = ready to apply, 10 = already up to date, 1 = failed.
#   apply     copy the staged program files into the Steam folder (Steam must be closed).
#   uninstall remove the loader and program files. config, plugins and themes always stay.
$steam = $env:SWX_STEAM_DIR
$stage = Join-Path $env:TEMP 'swarlex-millennium'
$loader = Join-Path $steam 'wsock32.dll'
$signer = 'SignPath Foundation'
# User data inside steam\millennium that an install must never overwrite
$keep = @('config', 'plugins', 'themes')

function Get-MillVersion {
    if (-not (Test-Path -LiteralPath $loader)) { return '' }
    $vi = (Get-Item -LiteralPath $loader).VersionInfo
    if ($vi.ProductName -notmatch 'Millennium') { return '' }
    return ([string]$vi.ProductVersion).Trim().TrimStart('v')
}
function Test-SteamRunning {
    # Only the Steam that lives in this folder counts; a process whose path cannot be read is treated as it
    $exe = Join-Path $steam 'steam.exe'
    return [bool](@(Get-Process steam -ErrorAction SilentlyContinue | Where-Object { -not $_.Path -or $_.Path -ieq $exe }).Count)
}
function Stop-MillProcesses {
    # Its helper processes can outlive Steam for a moment and would lock the files
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith((Join-Path $steam 'millennium'), 'OrdinalIgnoreCase') } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

switch ($env:SWX_MILL_MODE) {
    'prepare' {
        $installed = Get-MillVersion
        if (-not $installed -and (Test-Path -LiteralPath $loader)) {
            Say '[x] Steam\wsock32.dll belongs to another mod - left alone.' 'Red'
            Say '    Remove that mod first, then run Install / Update again.' 'Yellow'
            Write-History 'Millennium' 'failed - wsock32.dll is used by another mod'
            exit 1
        }
        try {
            $rel = Get-LatestRelease 'SteamClientHomebrew/Millennium' -Full
        } catch {
            Say ('[x] Could not reach GitHub: ' + $_.Exception.Message) 'Red'
            Write-History 'Millennium' 'failed - could not check for updates'
            exit 1
        }
        $latest = ([string]$rel.tag_name).TrimStart('v')
        $healthy = $installed -and (Test-Path -LiteralPath (Join-Path $steam 'millennium\lib\millennium.dll'))
        if ($installed) { Say ('[*] Installed: v' + $installed + '   Latest: v' + $latest) 'Cyan' } else { Say ('[*] Latest Millennium: v' + $latest) 'Cyan' }
        if ($healthy -and $installed -eq $latest -and $env:SWX_MILL_FORCE -ne '1') {
            Say '[+] Millennium is already up to date.' 'Green'
            Write-History 'Millennium' "already up to date [v$installed]"
            exit 10
        }
        $zipAsset = @($rel.assets | Where-Object { $_.name -match '-windows-x86_64\.zip$' })[0]
        $shaAsset = @($rel.assets | Where-Object { $_.name -match '-windows-x86_64\.sha256$' })[0]
        if (-not $zipAsset -or -not $shaAsset) {
            Say '[x] This Millennium release has no Windows download.' 'Red'
            Write-History 'Millennium' 'failed - no Windows download in the release'
            exit 1
        }
        try {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            New-Item -ItemType Directory -Path $stage | Out-Null
            $zip = Join-Path $stage $zipAsset.name
            $shaFile = Join-Path $stage $shaAsset.name
            Say ('[*] Downloading ' + $zipAsset.name + ' [' + (Format-Size ([long]$zipAsset.size)) + ']...') 'Cyan'
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri $zipAsset.browser_download_url -OutFile $zip
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri $shaAsset.browser_download_url -OutFile $shaFile
            $expected = (([IO.File]::ReadAllText($shaFile)).Trim() -split '\s+')[0]
            $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
            if (-not $expected -or $actual -ne $expected) { throw 'the download is corrupted - SHA-256 does not match' }
            $x = Join-Path $stage 'files'
            Expand-Archive -LiteralPath $zip -DestinationPath $x -Force
            $dll = @(Get-ChildItem -LiteralPath $x -Recurse -File -Filter 'wsock32.dll')[0]
            if (-not $dll) { throw 'the download does not contain wsock32.dll' }
            foreach ($bin in @(Get-ChildItem -LiteralPath $x -Recurse -File | Where-Object { $_.Extension -match '^\.(dll|exe)$' })) {
                $sig = Get-AuthenticodeSignature -FilePath $bin.FullName
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($signer)) {
                    throw ($bin.Name + ' is not signed by ' + $signer + ' [' + $sig.Status + '] - not installing it')
                }
            }
            [IO.File]::WriteAllText((Join-Path $stage 'root.txt'), $dll.DirectoryName)
            [IO.File]::WriteAllText((Join-Path $stage 'version.txt'), $latest)
            Say ('[+] Verified: SHA-256 and signatures (' + $signer + ').') 'Green'
            exit 0
        } catch {
            Say ('[x] ' + $_.Exception.Message) 'Red'
            Write-History 'Millennium' ('failed - ' + $_.Exception.Message)
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
            exit 1
        }
    }
    'apply' {
        try {
            $root = [IO.File]::ReadAllText((Join-Path $stage 'root.txt')).Trim()
            $ver = [IO.File]::ReadAllText((Join-Path $stage 'version.txt')).Trim()
            if (Test-SteamRunning) { throw 'Steam is still running - close it and try again' }
            Stop-MillProcesses
            Copy-Tree $root $steam @($keep | ForEach-Object { Join-Path $root ('millennium\' + $_) })
            $now = Get-MillVersion
            if ($now -ne $ver) { throw ('after copying, the loader reports version "' + $now + '"') }
            Say ('[+] Millennium v' + $ver + ' installed. Your themes, plugins and settings were kept.') 'Green'
            Write-History 'Millennium' ('installed v' + $ver)
            exit 0
        } catch {
            Say ('[x] Millennium was not installed: ' + $_.Exception.Message) 'Red'
            Write-History 'Millennium' ('failed - ' + $_.Exception.Message)
            exit 1
        } finally {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    'uninstall' {
        try {
            if (Test-SteamRunning) { throw 'Steam is still running - close it and try again' }
            Stop-MillProcesses
            $removed = 0
            # Only files that say they are Millennium's - another mod could also use one of these names
            foreach ($n in 'wsock32.dll', 'user32.dll', 'version.dll', 'dwmapi.dll') {
                $p = Join-Path $steam $n
                if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).VersionInfo.ProductName -match 'Millennium') {
                    Remove-Item -LiteralPath $p -Force
                    $removed++
                }
            }
            foreach ($d in 'bin', 'lib') {
                $p = Join-Path $steam ('millennium\' + $d)
                if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force; $removed++ }
            }
            if ($removed -eq 0) { Say '[-] Millennium is not installed.' 'DarkGray'; exit 0 }
            Say '[+] Millennium removed from Steam.' 'Green'
            Say ('    Themes, plugins and settings are kept in ' + (Join-Path $steam 'millennium')) 'DarkGray'
            Write-History 'Millennium' 'uninstalled - add-ons kept'
            exit 0
        } catch {
            Say ('[x] Could not remove Millennium: ' + $_.Exception.Message) 'Red'
            Write-History 'Millennium' ('uninstall failed - ' + $_.Exception.Message)
            exit 1
        }
    }
}
Say ('[x] Unknown Millennium mode: ' + $env:SWX_MILL_MODE) 'Red'
exit 1
::SWX_PS_END

::SWX_PS_BEGIN STEAMCACHE
# htmlcache is Steam's built-in browser cache (store, library, Millennium UI). The Steam login lives
# in the Steam folder's config, so it is not affected.
$result = Clear-CacheFolders @((Join-Path $env:LOCALAPPDATA 'Steam\htmlcache'))
Say ('[+] Steam web cache cleaned - freed ' + (Format-Size $result.Freed) + '. Login was kept.') 'Green'
Write-History 'Steam cache' ('freed ' + (Format-Size $result.Freed))
if ($result.Left -gt 0) { Say ('    ' + (Format-Size $result.Left) + ' could not be removed because Steam still had it open.') 'DarkGray' }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN MILLMANAGE
# Interactive Millennium add-on list. Nothing is changed while Steam runs (Millennium rewrites its config
# on its own): the wanted state is collected here, written to SWX_MILL_PENDING and the batch side closes
# Steam, runs MILLAPPLY and starts Steam again. Exit 3 = there are changes to apply, 0 = nothing to do.
$ind = ' ' * [int]$env:SWX_PAD
$mill = Join-Path $env:SWX_STEAM_DIR 'millennium'
$cfgFile = Join-Path $mill 'config\config.json'
$line = ([string][char]0x2500) * 64
$bar = ([string][char]0x2500) * 62

function Read-Json([string]$p) { try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }

$cfg = Read-Json $cfgFile
$enabled = @()
$active = 'default'
if ($cfg -and $cfg.plugins -and $cfg.plugins.enabledPlugins) { $enabled = @($cfg.plugins.enabledPlugins) }
if ($cfg -and $cfg.themes -and $cfg.themes.activeTheme) { $active = [string]$cfg.themes.activeTheme }

# The id Millennium stores is plugin.json's "name"; the folder name is the fallback
$plugins = @(Get-ChildItem -LiteralPath (Join-Path $mill 'plugins') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $j = Read-Json (Join-Path $_.FullName 'plugin.json')
    $id = if ($j -and $j.name) { [string]$j.name } else { $_.Name }
    $title = if ($j -and $j.common_name) { [string]$j.common_name } else { $id }
    [pscustomobject]@{ Id = $id; Title = $title; Version = [string]$j.version; Path = $_.FullName; On = ($enabled -contains $id); WasOn = ($enabled -contains $id); Delete = $false }
} | Sort-Object Title)
$themes = @(Get-ChildItem -LiteralPath (Join-Path $mill 'themes') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $j = Read-Json (Join-Path $_.FullName 'skin.json')
    $title = if ($j -and $j.name) { [string]$j.name } else { $_.Name }
    [pscustomobject]@{ Id = $_.Name; Title = $title; Version = [string]$j.version; Path = $_.FullName; Delete = $false }
} | Sort-Object Title)
$wantTheme = $active
$msg = $null
$msgColor = 'Gray'

function Test-Changed {
    if ($wantTheme -ne $active) { return $true }
    foreach ($p in $plugins) { if ($p.On -ne $p.WasOn -or $p.Delete) { return $true } }
    foreach ($t in $themes) { if ($t.Delete) { return $true } }
    return $false
}
function Fit([string]$s, [int]$w) { if ($s.Length -gt $w) { return $s.Substring(0, $w - 1) + '~' } return $s.PadRight($w) }

function Show-Screen {
    Clear-Host
    Write-Host ''; Write-Host ''
    Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Blue
    Write-Host ($ind + [char]0x2502) -ForegroundColor Blue -NoNewline
    Write-Host ('MILLENNIUM ADD-ONS'.PadLeft(40).PadRight(62)) -ForegroundColor White -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Blue
    Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Blue
    Write-Host ''
    $on = @($plugins | Where-Object { $_.On -and -not $_.Delete }).Count
    Write-Host ($ind + '  ' + $plugins.Count + ' plugins [' + $on + ' on], ' + $themes.Count + ' themes') -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ($ind + '  PLUGINS') -ForegroundColor Cyan
    if ($plugins.Count -eq 0) { Write-Host ($ind + '    none installed') -ForegroundColor DarkGray }
    for ($i = 0; $i -lt $plugins.Count; $i++) {
        $p = $plugins[$i]
        $changed = ($p.On -ne $p.WasOn) -or $p.Delete
        Write-Host ($ind + '  ' + ('{0,3}' -f ($i + 1)) + ' ') -ForegroundColor White -NoNewline
        if ($p.Delete) {
            Write-Host ([char]0x2716) -ForegroundColor Red -NoNewline
            Write-Host (' ' + (Fit $p.Title 36) + ' delete') -ForegroundColor Red
            continue
        }
        Write-Host ([char]0x25CF) -ForegroundColor $(if ($p.On) { 'Green' } else { 'DarkGray' }) -NoNewline
        Write-Host (' ' + (Fit $p.Title 36)) -ForegroundColor $(if ($p.On) { 'White' } else { 'DarkGray' }) -NoNewline
        Write-Host (' ' + (Fit $p.Version 10)) -ForegroundColor DarkGray -NoNewline
        Write-Host $(if ($changed) { ' *' } else { '' }) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host ($ind + '  THEMES') -ForegroundColor Cyan
    $useDefault = $wantTheme -eq 'default'
    Write-Host ($ind + '   t0 ') -ForegroundColor White -NoNewline
    Write-Host $(if ($useDefault) { [char]0x25C9 } else { [char]0x25CB }) -ForegroundColor $(if ($useDefault) { 'Green' } else { 'DarkGray' }) -NoNewline
    Write-Host (' ' + (Fit 'Steam default' 36)) -ForegroundColor $(if ($useDefault) { 'White' } else { 'DarkGray' }) -NoNewline
    Write-Host $(if ($useDefault -and $active -ne 'default') { ' *' } else { '' }) -ForegroundColor Yellow
    for ($i = 0; $i -lt $themes.Count; $i++) {
        $t = $themes[$i]
        Write-Host ($ind + '  ' + ('{0,3}' -f ('t' + ($i + 1))) + ' ') -ForegroundColor White -NoNewline
        if ($t.Delete) {
            Write-Host ([char]0x2716) -ForegroundColor Red -NoNewline
            Write-Host (' ' + (Fit $t.Title 36) + ' delete') -ForegroundColor Red
            continue
        }
        $isOn = $wantTheme -eq $t.Id
        Write-Host $(if ($isOn) { [char]0x25C9 } else { [char]0x25CB }) -ForegroundColor $(if ($isOn) { 'Green' } else { 'DarkGray' }) -NoNewline
        Write-Host (' ' + (Fit $t.Title 36)) -ForegroundColor $(if ($isOn) { 'White' } else { 'DarkGray' }) -NoNewline
        Write-Host (' ' + (Fit $t.Version 10)) -ForegroundColor DarkGray -NoNewline
        Write-Host $(if ($isOn -and $active -ne $t.Id) { ' *' } else { '' }) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    if ($msg) { Write-Host ($ind + '  ' + $msg) -ForegroundColor $msgColor }
    Write-Host ($ind + '  <number> plugin on/off   t<number> use theme   t0 Steam default') -ForegroundColor DarkGray
    Write-Host ($ind + '  del <number> / del t<number> delete   Enter = done') -ForegroundColor DarkGray
    if (Test-Changed) { Write-Host ($ind + '  * = pending. Applied when you leave - Steam restarts once.') -ForegroundColor Yellow }
    Write-Host ''
    Write-Host ($ind + '  ' + [char]0x203A) -ForegroundColor Blue -NoNewline
    Write-Host ' Choice: ' -ForegroundColor White -NoNewline
}

while ($true) {
    Show-Screen
    $in = [Console]::ReadLine()
    if ($null -eq $in) { break }
    $in = $in.Trim()
    if (-not $in -or $in -eq '0' -or $in -ieq 'b') { break }
    $m = [regex]::Match($in, '^(?i)(del(?:ete)?\s*)?(t)?\s*(\d+)$')
    if (-not $m.Success) { $msg = 'Type a number, t<number>, or del <number>.'; $msgColor = 'Red'; continue }
    $isDel = $m.Groups[1].Success
    $isTheme = $m.Groups[2].Success
    $n = [int]$m.Groups[3].Value
    $msg = $null
    if ($isTheme) {
        if ($n -eq 0) {
            if ($isDel) { $msg = 'The Steam default theme cannot be deleted.'; $msgColor = 'Red'; continue }
            $wantTheme = 'default'; continue
        }
        if ($n -lt 1 -or $n -gt $themes.Count) { $msg = "There is no theme t$n."; $msgColor = 'Red'; continue }
        $t = $themes[$n - 1]
        if ($isDel) {
            $t.Delete = -not $t.Delete
            # Deleting the theme in use falls back to Steam's own look, the same thing Millennium does
            if ($t.Delete -and $wantTheme -eq $t.Id) { $wantTheme = 'default' }
        } elseif ($t.Delete) {
            $msg = $t.Title + ' is marked for deletion - del t' + $n + ' again to keep it.'; $msgColor = 'Yellow'
        } else {
            $wantTheme = $t.Id
        }
        continue
    }
    if ($n -lt 1 -or $n -gt $plugins.Count) { $msg = "There is no plugin $n."; $msgColor = 'Red'; continue }
    $p = $plugins[$n - 1]
    if ($isDel) { $p.Delete = -not $p.Delete }
    elseif ($p.Delete) { $msg = $p.Title + ' is marked for deletion - del ' + $n + ' again to keep it.'; $msgColor = 'Yellow' }
    else { $p.On = -not $p.On }
}

if (-not (Test-Changed)) { exit 0 }
$pending = [pscustomobject]@{
    enabledPlugins = @($plugins | Where-Object { $_.On -and -not $_.Delete } | ForEach-Object { $_.Id })
    activeTheme    = $wantTheme
    # Folder names only ("plugins\name"); MILLAPPLY rebuilds the path inside the millennium folder itself
    delete         = @(@($plugins | Where-Object { $_.Delete } | ForEach-Object { 'plugins\' + (Split-Path $_.Path -Leaf) }) + @($themes | Where-Object { $_.Delete } | ForEach-Object { 'themes\' + (Split-Path $_.Path -Leaf) }))
    managed        = @($plugins | ForEach-Object { $_.Id })
}
[IO.File]::WriteAllText($env:SWX_MILL_PENDING, (ConvertTo-Json -InputObject $pending -Depth 5), (New-Object Text.UTF8Encoding $false))
exit 3
::SWX_PS_END

::SWX_PS_BEGIN MILLAPPLY
# Applies what MILLMANAGE collected, with Steam closed. config.json is edited in place (only enabledPlugins
# and activeTheme) after a copy is kept as config.json.swarlex-backup; deleted add-ons go to the Recycle Bin.
$mill = Join-Path $env:SWX_STEAM_DIR 'millennium'
$cfgFile = Join-Path $mill 'config\config.json'
try {
    $want = Get-Content -LiteralPath $env:SWX_MILL_PENDING -Raw -Encoding UTF8 | ConvertFrom-Json
    $steamExe = Join-Path $env:SWX_STEAM_DIR 'steam.exe'
    if (@(Get-Process steam -ErrorAction SilentlyContinue | Where-Object { -not $_.Path -or $_.Path -ieq $steamExe }).Count) { throw 'Steam is still running' }
    if (Test-Path -LiteralPath $cfgFile) {
        Copy-Item -LiteralPath $cfgFile -Destination ($cfgFile + '.swarlex-backup') -Force
        $cfg = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path (Split-Path $cfgFile) -Force | Out-Null
        $cfg = [pscustomobject]@{}
    }
    if (-not $cfg.plugins) { $cfg | Add-Member -NotePropertyName plugins -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $cfg.themes) { $cfg | Add-Member -NotePropertyName themes -NotePropertyValue ([pscustomobject]@{}) -Force }
    # Ids Millennium lists but that have no folder here (not managed by the list) are left as they were
    $keep = @(@($cfg.plugins.enabledPlugins) | Where-Object { $_ -and @($want.managed) -notcontains $_ })
    $cfg.plugins | Add-Member -NotePropertyName enabledPlugins -NotePropertyValue ([object[]](@($keep) + @($want.enabledPlugins))) -Force
    $cfg.themes | Add-Member -NotePropertyName activeTheme -NotePropertyValue ([string]$want.activeTheme) -Force
    [IO.File]::WriteAllText($cfgFile, (ConvertTo-Json -InputObject $cfg -Depth 30), (New-Object Text.UTF8Encoding $false))

    Add-Type -AssemblyName Microsoft.VisualBasic
    $deleted = @()
    foreach ($entry in @($want.delete)) {
        # Only a single folder directly inside millennium\plugins or millennium\themes, nothing else
        $kind, $name = ([string]$entry -split '\\', 2)
        if (@('plugins', 'themes') -notcontains $kind -or -not $name -or $name -match '[\\/:*?"<>|]' -or $name -match '^\.+$') { continue }
        $full = Join-Path (Join-Path $mill $kind) $name
        if (Test-Path -LiteralPath $full -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($full, 'OnlyErrorDialogs', 'SendToRecycleBin')
            $deleted += $name
        }
    }
    $count = @($want.enabledPlugins).Count
    $summary = ([string]$count + $(if ($count -eq 1) { ' plugin on' } else { ' plugins on' }) + ', theme ' + $want.activeTheme)
    if ($deleted.Count) { $summary += ', deleted ' + ($deleted -join ', ') }
    Say ('[+] Millennium add-ons updated: ' + $summary) 'Green'
    if ($deleted.Count) { Say '    Deleted add-ons are in the Recycle Bin.' 'DarkGray' }
    Write-History 'Millennium' $summary
    exit 0
} catch {
    Say ('[x] Could not apply the changes: ' + $_.Exception.Message) 'Red'
    Write-History 'Millennium' ('add-on changes failed - ' + $_.Exception.Message)
    exit 1
} finally {
    Remove-Item -LiteralPath $env:SWX_MILL_PENDING -Force -ErrorAction SilentlyContinue
}
::SWX_PS_END

::SWX_PS_BEGIN SNAPLIST
# Lists the safety snapshots newest first and writes their paths, one per line in the same order, to
# SWX_SNAP_PICK; the batch side asks for the choice. Exit 1 = there are none.
$ind = ' ' * [int]$env:SWX_PAD
$dir = Join-Path $env:SWX_DATA 'snapshots'
$names = @{ vencord = 'Vencord update'; spicetify = 'Spicetify update'; millennium = 'Millennium change' }
$snaps = @(Get-ChildItem -LiteralPath $dir -Filter '*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 12)
if ($snaps.Count -eq 0) {
    Say '[-] No snapshots yet - one is taken before every update.' 'DarkGray'
    exit 1
}
Write-Host ($ind + '  Saved automatically right before these changes - newest first:') -ForegroundColor DarkGray
Write-Host ''
for ($i = 0; $i -lt $snaps.Count; $i++) {
    $kind = ($snaps[$i].BaseName -split '_')[0]
    $label = if ($names.ContainsKey($kind)) { $names[$kind] } else { $kind }
    Write-Host ($ind + '  ' + ('{0,3}' -f ($i + 1)) + '  ') -ForegroundColor White -NoNewline
    Write-Host ('before ' + $label).PadRight(30) -ForegroundColor Cyan -NoNewline
    Write-Host $snaps[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm') -ForegroundColor DarkGray
}
[IO.File]::WriteAllLines($env:SWX_SNAP_PICK, [string[]]@($snaps | ForEach-Object { $_.FullName }))
exit 0
::SWX_PS_END

::SWX_PS_BEGIN SYSINFO
# Versions of everything Swarlex manages, for troubleshooting. Also writes a plain-text copy to
# SWX_SYSINFO_FILE; the batch side asks whether to copy it (SYSCOPY).
$ErrorActionPreference = 'Continue'
$ind = ' ' * [int]$env:SWX_PAD
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$section, [string]$name, [string]$value) { $rows.Add([pscustomobject]@{ Section = $section; Name = $name; Value = $(if ($value) { $value } else { '-' }) }) }
function Get-FileVer([string]$p) { if (Test-Path -LiteralPath $p) { $v = (Get-Item -LiteralPath $p).VersionInfo; return ('{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart) } return '' }
function Get-Cmd([string]$exe, [string[]]$cmdArgs) {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { return 'not installed' }
    return "$(@(& $exe @cmdArgs 2>$null) | Select-Object -First 1)".Trim()
}

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
Add-Row 'SYSTEM' 'Windows' $(if ($os) { $os.Caption.Replace('Microsoft ', '') + ' ' + $os.Version } else { '' })
Add-Row 'SYSTEM' 'Privilege' $(if ($env:IS_ADMIN -eq '1') { 'Administrator' } else { 'Standard' })
Add-Row 'SYSTEM' 'PowerShell' ([string]$PSVersionTable.PSVersion)
$self = Get-Item -LiteralPath $env:SWX_SELF
Add-Row 'SYSTEM' 'Swarlex' ('v' + $env:SWX_VERSION + ' (' + $self.LastWriteTime.ToString('yyyy-MM-dd') + ')' + $(if ($env:CFG_AUTOUPD -eq 'off') { ', auto-update off' } else { '' }))

foreach ($f in 'Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment') {
    $app = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA $f) -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($app) {
        $patched = Test-Path -LiteralPath (Join-Path $app.FullName 'resources\_app.asar')
        Add-Row 'DISCORD' $(if ($f -eq 'Discord') { 'Discord' } else { $f -replace '^Discord', 'Discord ' }) (($app.Name -replace '^app-', '') + $(if ($patched) { ', patched' } else { ', not patched' }))
    }
}
$vd = $env:SWX_VENCORD_DIR
if ($vd -and (Test-Path -LiteralPath (Join-Path $vd 'package.json'))) {
    $commit = "$(& git -C $vd log -1 --format='%h  %cd' --date=short 2>$null)".Trim()
    Add-Row 'DISCORD' 'Vencord' $commit
    $up = Join-Path $vd 'src\userplugins'
    $n = @(Get-ChildItem -LiteralPath $up -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Name.StartsWith('.') -or $_.Name.StartsWith('_')) }).Count
    $off = @(Get-ChildItem -LiteralPath (Join-Path $up '.disabled') -ErrorAction SilentlyContinue).Count
    Add-Row 'DISCORD' 'Userplugins' ([string]$n + ' on, ' + $off + ' off')
} else { Add-Row 'DISCORD' 'Vencord' 'not set up' }
Add-Row 'DISCORD' 'Node.js' (Get-Cmd 'node' @('--version'))
Add-Row 'DISCORD' 'pnpm' (Get-Cmd 'pnpm' @('--version'))
Add-Row 'DISCORD' 'Git' ((Get-Cmd 'git' @('--version')) -replace '^git version ', '')

$sp = Get-FileVer (Join-Path $env:APPDATA 'Spotify\Spotify.exe')
Add-Row 'SPOTIFY' 'Spotify' $(if ($sp) { $sp } elseif (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\Spotify.exe')) { 'Microsoft Store version' } else { 'not installed' })
Add-Row 'SPOTIFY' 'Spicetify' (Get-Cmd 'spicetify' @('-v'))

$steam = [string]$env:SWX_STEAM_DIR
if ($steam -and (Test-Path -LiteralPath (Join-Path $steam 'steam.exe'))) {
    $manifest = Join-Path $steam 'package\steam_client_win32.manifest'
    $build = if (Test-Path -LiteralPath $manifest) { ([regex]::Match([IO.File]::ReadAllText($manifest), '"version"\s+"(\d+)"')).Groups[1].Value } else { '' }
    Add-Row 'STEAM' 'Steam' $(if ($build) { 'build ' + $build } else { Get-FileVer (Join-Path $steam 'steam.exe') })
    $loader = Join-Path $steam 'wsock32.dll'
    $mv = if (Test-Path -LiteralPath $loader) { $vi = (Get-Item -LiteralPath $loader).VersionInfo; if ($vi.ProductName -match 'Millennium') { [string]$vi.ProductVersion } else { 'wsock32.dll is another mod' } } else { 'not installed' }
    Add-Row 'STEAM' 'Millennium' $mv
    $mp = @(Get-ChildItem -LiteralPath (Join-Path $steam 'millennium\plugins') -Directory -ErrorAction SilentlyContinue).Count
    $mt = @(Get-ChildItem -LiteralPath (Join-Path $steam 'millennium\themes') -Directory -ErrorAction SilentlyContinue).Count
    Add-Row 'STEAM' 'Add-ons' ([string]$mp + ' plugins, ' + $mt + ' themes')
} else { Add-Row 'STEAM' 'Steam' 'not installed' }

$section = ''
foreach ($r in $rows) {
    if ($r.Section -ne $section) { if ($section) { Write-Host '' }; Write-Host ($ind + '  ' + $r.Section) -ForegroundColor Cyan; $section = $r.Section }
    Write-Host ($ind + '    ' + $r.Name.PadRight(16)) -ForegroundColor White -NoNewline
    Write-Host $r.Value -ForegroundColor $(if ($r.Value -match 'not |another mod|^-$') { 'DarkGray' } else { 'Gray' })
}
$report = @('Swarlex Manager - system info [' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ']')
$section = ''
foreach ($r in $rows) { if ($r.Section -ne $section) { $report += ''; $report += $r.Section; $section = $r.Section }; $report += ('  ' + $r.Name.PadRight(16) + $r.Value) }
if ($env:SWX_SYSINFO_FILE) { [IO.File]::WriteAllText($env:SWX_SYSINFO_FILE, ($report -join "`r`n"), (New-Object Text.UTF8Encoding $false)) }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN SYSCOPY
Set-Clipboard -Value ([IO.File]::ReadAllText($env:SWX_SYSINFO_FILE))
Say '[+] Copied to the clipboard - paste it anywhere with Ctrl+V.' 'Green'
exit 0
::SWX_PS_END

::SWX_PS_BEGIN BACKUP
# Full backup (SWX_SNAP_KIND empty): everything, as Desktop\Swarlex_Backup_<time>.zip.
# Safety snapshot (SWX_SNAP_KIND = vencord / spicetify / millennium): only what that change can touch,
# kept in %APPDATA%\Swarlex Manager\snapshots (newest 5 per kind) for Backup > Undo Last Update.
# Both use the same zip layout, so RESTORE handles either.
$kind = [string]$env:SWX_SNAP_KIND
$snap = [bool]$kind
$want = if ($snap) { @{ vencord = @('Vencord', 'userplugins'); spicetify = @('spicetify'); millennium = @('millennium') }[$kind] } else { @('Vencord', 'userplugins', 'spicetify', 'millennium') }
if (-not $want) { Say ('[x] Unknown snapshot kind: ' + $kind) 'Red'; exit 1 }
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
if ($snap) {
    $snapDir = Join-Path $env:SWX_DATA 'snapshots'
    New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    $zip = Join-Path $snapDir ($kind + '_' + $ts + '.zip')
} else {
    $zip = Join-Path $env:SWX_DESK ('Swarlex_Backup_' + $ts + '.zip')
}
$stage = Join-Path $env:TEMP ('swarlex-backup-' + $ts)
$parts = @()
$failed = $null
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $vencordData = Join-Path $env:APPDATA 'Vencord'
    if ($want -contains 'Vencord' -and (Test-Path -LiteralPath $vencordData)) {
        Copy-Tree $vencordData (Join-Path $stage 'Vencord')
        $parts += 'Vencord settings'
    }
    if ($want -contains 'userplugins' -and $env:SWX_VENCORD_DIR) {
        $plugins = Join-Path $env:SWX_VENCORD_DIR 'src\userplugins'
        if (Test-Path -LiteralPath $plugins) {
            Copy-Tree $plugins (Join-Path $stage 'userplugins') @('node_modules', (Join-Path $plugins '.swarlex-testing'))
            $count = @(Get-ChildItem -LiteralPath $plugins -Force | Where-Object { -not ($_.Name.StartsWith('.') -or $_.Name.StartsWith('_')) }).Count
            $parts += ([string]$count + ' userplugins')
        }
        if ($snap) {
            # The commit before the update, so Undo can also put the Vencord source back
            # Optional: a Vencord folder that is not a git checkout, or no git at all, still gets its snapshot.
            # PowerShell 5.1 turns any stderr of a native command into an exception under 'Stop', hence Continue.
            $head = ''
            if (Get-Command git -ErrorAction SilentlyContinue) {
                $ErrorActionPreference = 'Continue'
                $head = "$(@(& git -C $env:SWX_VENCORD_DIR rev-parse HEAD 2>$null) | Select-Object -First 1)".Trim()
                $ErrorActionPreference = 'Stop'
            }
            if ($head -match '^[0-9a-f]{40}$') { [IO.File]::WriteAllText((Join-Path $stage 'vencord-head.txt'), $head) }
        }
    }
    $spiceData = Join-Path $env:APPDATA 'spicetify'
    if ($want -contains 'spicetify' -and (Test-Path -LiteralPath $spiceData)) {
        # Backup/Extracted are Spicetify's copy of Spotify's own files; they are version specific and rebuilt by "spicetify backup"
        Copy-Tree $spiceData (Join-Path $stage 'spicetify') @((Join-Path $spiceData 'Backup'), (Join-Path $spiceData 'Extracted'))
        $parts += 'Spicetify'
    }
    if ($want -contains 'millennium' -and $env:SWX_STEAM_DIR) {
        # Only the user's part of Millennium: bin and lib are program files that Install / Update brings back
        $mill = Join-Path $env:SWX_STEAM_DIR 'millennium'
        if (Test-Path -LiteralPath $mill) {
            Copy-Tree $mill (Join-Path $stage 'millennium') @((Join-Path $mill 'bin'), (Join-Path $mill 'lib'))
            $parts += 'Millennium add-ons'
        }
    }
    # Snapshots carry a fingerprint (paths, sizes, times - robocopy keeps the originals' times). If nothing
    # changed since the newest snapshot of this kind, no new one is made: otherwise five "already up to
    # date" runs in a row would push the one snapshot that matters out of the last five.
    $sig = $null
    $unchanged = $false
    if ($snap -and $parts.Count -gt 0) {
        # TEMP is often an 8.3 path (C:\Users\NAME~1\...) while FullName comes back long, so the base
        # for the relative paths is taken from the listing itself
        $base = (Get-Item -LiteralPath (Get-ChildItem -LiteralPath $stage -Force | Select-Object -First 1).FullName).Parent.FullName
        $items = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length)
            if ($_.Name -eq 'vencord-head.txt') { $rel + '=' + [IO.File]::ReadAllText($_.FullName) } else { $rel + '=' + $_.Length + '@' + $_.LastWriteTimeUtc.Ticks }
        })
        $sha = [Security.Cryptography.SHA256]::Create()
        $sig = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($items -join "`n")))).Replace('-', '')
        $last = Get-ChildItem -LiteralPath $snapDir -Filter ($kind + '_*.zip') | Sort-Object Name -Descending | Select-Object -First 1
        if ($last) {
            $lastSig = [IO.Path]::ChangeExtension($last.FullName, '.sig')
            if ((Test-Path -LiteralPath $lastSig) -and ([IO.File]::ReadAllText($lastSig).Trim() -eq $sig)) { $unchanged = $true }
        }
    }
    if ($parts.Count -gt 0 -and -not $unchanged) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
        if ($sig) { [IO.File]::WriteAllText([IO.Path]::ChangeExtension($zip, '.sig'), $sig) }
    }
} catch {
    $failed = $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($snap) {
    # A snapshot must never stop the change it protects - it warns and lets it continue
    if ($failed) {
        Say ('[!] Could not save a safety snapshot: ' + $failed) 'Yellow'
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
        exit 0
    }
    if ($parts.Count -eq 0) { exit 0 }
    if ($unchanged) {
        Say '[-] Nothing changed since the last snapshot - kept that one.' 'DarkGray'
        exit 0
    }
    foreach ($old in @(Get-ChildItem -LiteralPath $snapDir -Filter ($kind + '_*.zip') | Sort-Object Name -Descending | Select-Object -Skip 5)) {
        Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($old.FullName, '.sig')) -Force -ErrorAction SilentlyContinue
    }
    Say ('[+] Safety snapshot saved [' + ($parts -join ', ') + '] - Backup > Undo can roll back.') 'DarkGray'
    Write-Log 'INFO' ('Safety snapshot ' + (Split-Path $zip -Leaf) + ': ' + ($parts -join ', '))
    exit 0
}
if ($failed) {
    Say ('[x] Backup failed: ' + $failed) 'Red'
    Write-History 'Backup' 'failed'
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    exit 1
}
if ($parts.Count -eq 0) { Say '[*] Found no Vencord, Spicetify or Millennium data to back up.' 'Yellow'; exit 1 }
$mb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
Say ('[+] Backed up: ' + ($parts -join ', ')) 'Green'
Write-History 'Backup' ('saved ' + (Split-Path $zip -Leaf) + ' [' + $mb + ' MB]')
Say ('    ' + $zip + '  [' + $mb + ' MB]') 'DarkGray'
exit 0
::SWX_PS_END

::SWX_PS_BEGIN RESTORE
# config-xpui.ini also holds what only fits this PC: where Spotify is, and which Spotify version
# Spicetify's own backup of it belongs to. Those keep this PC's values; everything else comes from
# the backup. Taken from another PC or an older Spotify they would stop Spicetify from applying.
function Merge-SpiceIni([string]$path, [string]$before) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $text = [IO.File]::ReadAllText($path)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $mine = @{}
    $myBackup = $null
    if ($before) {
        $sec = ''
        foreach ($l in ($before -split "`r?`n")) {
            if ($l -match '^\s*\[(.+?)\]') { $sec = $Matches[1]; if ($sec -eq 'Backup') { $myBackup = @() }; continue }
            if ($sec -eq 'Setting' -and $l -match '^\s*(spotify_path|prefs_path)\s*=\s*(.*)$') { $mine[$Matches[1]] = $Matches[2].Trim() }
            if ($sec -eq 'Backup' -and $l.Trim()) { $myBackup += $l }
        }
    }
    $defaults = @{ spotify_path = (Join-Path $env:APPDATA 'Spotify'); prefs_path = (Join-Path $env:APPDATA 'Spotify\prefs') }
    $out = New-Object Collections.Generic.List[string]
    $sec = ''
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^\s*\[(.+?)\]') {
            $sec = $Matches[1]
            $out.Add($l)
            if ($sec -eq 'Backup' -and $null -ne $myBackup) { foreach ($b in $myBackup) { $out.Add($b) } }
            continue
        }
        if ($sec -eq 'Backup') {
            if ($null -ne $myBackup) { if (-not $l.Trim()) { $out.Add($l) }; continue }
            # No Spicetify backup on this PC yet: an empty one makes Spicetify take a fresh one
            if ($l -match '^(\s*(version|with)\s*=).*$') { $out.Add($Matches[1] + ' '); continue }
        }
        if ($sec -eq 'Setting' -and $l -match '^(\s*(spotify_path|prefs_path)\s*=\s*)(.*)$') {
            $key = $Matches[2]; $lead = $Matches[1]; $val = $Matches[3].Trim()
            $pick = ''
            foreach ($c in @($mine[$key], $val, $defaults[$key])) { if ($c -and (Test-Path -LiteralPath $c)) { $pick = $c; break } }
            $out.Add($lead + $pick)
            continue
        }
        $out.Add($l)
    }
    [IO.File]::WriteAllText($path, ($out -join $nl), (New-Object Text.UTF8Encoding $false))
}

$stage = Join-Path $env:TEMP ('swarlex-restore-' + [guid]::NewGuid().ToString('N'))
$done = @()
$failed = $null
try {
    Expand-Archive -LiteralPath $env:SWX_ZIP -DestinationPath $stage -Force
    $targets = [ordered]@{
        'Vencord'   = (Join-Path $env:APPDATA 'Vencord')
        'spicetify' = (Join-Path $env:APPDATA 'spicetify')
    }
    if ($env:SWX_VENCORD_DIR -and (Test-Path -LiteralPath (Join-Path $env:SWX_VENCORD_DIR 'src'))) {
        $targets['userplugins'] = Join-Path $env:SWX_VENCORD_DIR 'src\userplugins'
    } elseif (Test-Path -LiteralPath (Join-Path $stage 'userplugins')) {
        # Kept until Vencord is set up (Discord > Patch Discord), which then puts them in place
        $pending = Join-Path $env:SWX_DATA 'pending-userplugins'
        Copy-Tree (Join-Path $stage 'userplugins') $pending
        Say '[*] Userplugins are kept until Vencord is set up.' 'Cyan'
        Say '    Discord > [1] Patch Discord puts them in place.' 'DarkGray'
        $done += 'userplugins (pending)'
    }
    if ($env:SWX_STEAM_DIR -and (Test-Path -LiteralPath (Join-Path $env:SWX_STEAM_DIR 'steam.exe'))) {
        $targets['millennium'] = Join-Path $env:SWX_STEAM_DIR 'millennium'
    } elseif (Test-Path -LiteralPath (Join-Path $stage 'millennium')) {
        Say '[!] Skipped Millennium add-ons - Steam was not found.' 'Yellow'
    }
    $spiceIni = Join-Path $targets['spicetify'] 'config-xpui.ini'
    $iniBefore = if (Test-Path -LiteralPath $spiceIni) { [IO.File]::ReadAllText($spiceIni) } else { '' }
    foreach ($name in @($targets.Keys)) {
        $from = Join-Path $stage $name
        if (Test-Path -LiteralPath $from) {
            Copy-Tree $from $targets[$name]
            $done += $name
        }
    }
    if ($done -contains 'spicetify') { Merge-SpiceIni $spiceIni $iniBefore }
    # Safety snapshots of a Vencord update carry the commit from before it; the batch side puts it back
    $headFile = Join-Path $stage 'vencord-head.txt'
    if ($env:SWX_ROLLBACK_FILE -and (Test-Path -LiteralPath $headFile)) { Copy-Item -LiteralPath $headFile -Destination $env:SWX_ROLLBACK_FILE -Force }
} catch {
    $failed = $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
$label = if ($env:SWX_RESTORE_LABEL) { $env:SWX_RESTORE_LABEL } else { 'Restore backup' }
if ($failed) { Say ('[x] Restore failed: ' + $failed) 'Red'; Write-History $label 'failed'; exit 1 }
if ($done.Count -eq 0) { Say '[x] The backup has no Vencord, Spicetify or Millennium data.' 'Red'; exit 1 }
# The batch side applies Spicetify and offers Millennium afterwards, so the restored setup is active
if ($env:SWX_RESTORED_FILE) { [IO.File]::WriteAllLines($env:SWX_RESTORED_FILE, [string[]]$done) }
Say ('[+] Restored: ' + ($done -join ', ')) 'Green'
Write-History $label (($done -join ', ') + ' from ' + (Split-Path $env:SWX_ZIP -Leaf))
if ($done -contains 'userplugins' -and -not $env:SWX_ROLLBACK_FILE) { Say '    Run Patch Discord to build the restored plugins in.' 'DarkGray' }
exit 0
::SWX_PS_END

::SWX_PS_BEGIN REPAIRSCAN
# Read-only health check for :ACTION_REPAIR. Prints one row per check and writes the fixes it wants to
# SWX_REPAIR_FILE, one "key" or "key=value" per line. Exit code: problems Repair can fix (99 = scan failed).
# Row states: ok, fix (Repair fixes it), bad (needs the user), info (not a problem).
$ErrorActionPreference = 'Continue'
$fixes = New-Object System.Collections.Generic.List[string]
$script:fixable = 0
$script:manual = 0

function Row([string]$state, [string]$label, [string]$detail) {
    $mark = @{ ok = '[+]'; fix = '[!]'; bad = '[x]'; info = '[-]' }[$state]
    $color = @{ ok = 'Green'; fix = 'Yellow'; bad = 'Red'; info = 'DarkGray' }[$state]
    if ($state -eq 'fix' -or $state -eq 'bad') { Write-Log 'WARN' ('Repair scan: ' + $label + ' - ' + $detail) }
    if ($detail.Length -gt 41) { $detail = $detail.Substring(0, 40) + '~' }
    Write-Host ($pad + $mark + ' ') -ForegroundColor $color -NoNewline
    Write-Host $label.PadRight(17) -ForegroundColor White -NoNewline
    Write-Host $detail -ForegroundColor $(if ($state -eq 'fix' -or $state -eq 'bad') { $color } else { 'DarkGray' })
    if ($state -eq 'fix') { $script:fixable++ }
    if ($state -eq 'bad') { $script:manual++ }
}
function Need([string]$key) { if (-not $fixes.Contains($key)) { $fixes.Add($key) } }
function Section([string]$title) { Write-Host ''; Write-Host ($pad + $title) -ForegroundColor Cyan }

try {
    # ---------------- Discord & Vencord ----------------
    Section 'DISCORD & VENCORD'
    $flavors = @()
    foreach ($name in 'Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment') {
        $root = Join-Path $env:LOCALAPPDATA $name
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $apps = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources') } | Sort-Object LastWriteTime -Descending)
        if ($apps.Count -gt 0) { $flavors += [pscustomobject]@{ Name = $name; Apps = $apps } }
    }
    $vdir = $env:SWX_VENCORD_DIR
    $hasVencord = [bool]($vdir -and (Test-Path -LiteralPath (Join-Path $vdir 'package.json')))
    $patcher = if ($vdir) { Join-Path $vdir 'dist\patcher.js' } else { '' }

    if ($flavors.Count -eq 0) { Row info 'Discord' 'not installed' }
    if (-not $hasVencord) {
        Row info 'Vencord' 'not set up - use Discord > Patch Discord'
    } else {
        $missing = @('git', 'node', 'pnpm' | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($missing.Count -gt 0) { Row fix 'Build tools' ('missing: ' + ($missing -join ', ')); Need 'tools' }
        else { Row ok 'Build tools' 'git, node and pnpm found' }

        $gitDir = Join-Path $vdir '.git'
        if ((Test-Path -LiteralPath $gitDir) -and $missing -notcontains 'git') {
            $head = (@(& git -C $vdir rev-parse --short HEAD 2>&1) | ForEach-Object { "$_" }) -join ' '
            $repoOk = $true
            if ($head -match 'dubious ownership') {
                Row fix 'Vencord repo' 'git does not trust the folder owner'; Need 'safedir'; $repoOk = $false
            } else {
                $gitBusy = @(Get-Process git -ErrorAction SilentlyContinue).Count -gt 0
                if ((Test-Path -LiteralPath (Join-Path $gitDir 'index.lock')) -and -not $gitBusy) {
                    Row fix 'Git lock' 'leftover index.lock blocks updates'; Need 'gitlock'; $repoOk = $false
                }
                if (Test-Path -LiteralPath (Join-Path $gitDir 'MERGE_HEAD')) {
                    Row fix 'Git merge' 'an update stopped halfway'; Need 'gitabort=merge'; $repoOk = $false
                } elseif ((Test-Path -LiteralPath (Join-Path $gitDir 'rebase-merge')) -or (Test-Path -LiteralPath (Join-Path $gitDir 'rebase-apply'))) {
                    Row fix 'Git rebase' 'a rebase stopped halfway'; Need 'gitabort=rebase'; $repoOk = $false
                }
            }
            if ($repoOk) { Row ok 'Vencord repo' ('healthy [' + $head.Trim() + ']') }
        }

        if (Test-Path -LiteralPath (Join-Path $vdir 'src\userplugins\.swarlex-testing')) {
            Row fix 'Userplugins' 'left parked by an interrupted check'; Need 'recover'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $vdir 'node_modules'))) {
            Row fix 'Vencord build' 'dependencies are missing'; Need 'build'
        } elseif (-not (Test-Path -LiteralPath $patcher)) {
            Row fix 'Vencord build' 'dist\patcher.js is missing'; Need 'build'
        } else {
            Row ok 'Vencord build' ('built ' + (Get-Item -LiteralPath $patcher).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        }
    }

    $toPatch = @()
    $toUnpatch = @()
    foreach ($f in $flavors) {
        $label = if ($f.Name -eq 'Discord') { 'Discord Stable' } else { 'Discord ' + ($f.Name -replace '^Discord', '') }
        $ver = $f.Apps[0].Name -replace '^app-', ''
        $res = Join-Path $f.Apps[0].FullName 'resources'
        $cur = Get-Item -LiteralPath (Join-Path $res 'app.asar') -ErrorAction SilentlyContinue
        $isStub = [bool]($cur -and ($cur.PSIsContainer -or $cur.Length -lt 64KB))
        if (Test-Path -LiteralPath (Join-Path $res '_app.asar')) {
            # Patched: the stub must point at a patcher.js that exists, or Discord will not start
            $points = $null
            if ($isStub -and -not $cur.PSIsContainer) {
                $txt = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($cur.FullName))
                $m = [regex]::Match($txt, 'require\(("(?:[^"\\]|\\.)*")\)')
                if ($m.Success) { try { $points = [string](ConvertFrom-Json $m.Groups[1].Value) } catch { } }
            }
            $ours = $hasVencord -and $points -and ([IO.Path]::GetFullPath($points) -ieq [IO.Path]::GetFullPath($patcher))
            if (-not $cur) {
                if ($hasVencord) { Row fix $label "$ver - the Vencord patch file is gone"; $toPatch += $f.Name }
                else { Row fix $label "$ver - broken patch, won't start"; $toUnpatch += $f.Name }
            } elseif (-not $isStub) {
                if ($hasVencord) { Row fix $label "$ver - Discord overwrote the patch"; $toPatch += $f.Name }
                else { Row info $label "$ver - not patched" }
            } elseif (-not $points -or -not (Test-Path -LiteralPath $points)) {
                if ($hasVencord) { Row fix $label "$ver - points to a missing build"; $toPatch += $f.Name }
                else { Row fix $label "$ver - broken patch, won't start"; $toUnpatch += $f.Name }
            } elseif ($ours) {
                Row ok $label "$ver - patched"
            } else {
                Row info $label "$ver - patched by another Vencord"
            }
        } elseif ($isStub) {
            Row bad $label "$ver - damaged, reinstall Discord"
        } elseif (-not $cur) {
            Row bad $label "$ver - files missing, reinstall"
        } else {
            # Discord keeps the previous app-* folder after an update; if that one was patched, the update removed Vencord
            $wasPatched = @($f.Apps | Select-Object -Skip 1 | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources\_app.asar') }).Count -gt 0
            if ($wasPatched -and $hasVencord) { Row fix $label "$ver - update removed Vencord"; $toPatch += $f.Name }
            else { Row info $label "$ver - not patched" }
        }
    }
    if ($toPatch.Count -gt 0) {
        if ($hasVencord -and -not (Test-Path -LiteralPath $patcher)) { Need 'build' }
        Need ('patch=' + ($toPatch -join ','))
    }
    if ($toUnpatch.Count -gt 0) { Need ('unpatch=' + ($toUnpatch -join ',')) }

    # ---------------- Spotify & Spicetify ----------------
    Section 'SPOTIFY & SPICETIFY'
    $spDir = Join-Path $env:APPDATA 'Spotify'
    $spExe = Join-Path $spDir 'Spotify.exe'
    $spVer = $null
    if (Test-Path -LiteralPath $spExe) {
        # Built from the numeric parts: FileVersion can carry extra text after the number
        $vi = (Get-Item -LiteralPath $spExe).VersionInfo
        $spVer = '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
        Row ok 'Spotify' ('installed [' + $spVer + ']')
    } elseif (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\Spotify.exe')) {
        Row bad 'Spotify' 'Store app - get it from spotify.com'
    } else {
        Row info 'Spotify' 'not installed'
    }

    $cfgDir = Join-Path $env:APPDATA 'spicetify'
    $cli = Get-Command spicetify -ErrorAction SilentlyContinue
    $used = (Test-Path -LiteralPath $cfgDir) -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'spicetify'))
    if (-not $cli) {
        if ($used -and $spVer) { Row fix 'Spicetify CLI' 'missing - will be reinstalled'; Need 'spicetools' }
        else { Row info 'Spicetify' 'not set up' }
    } else {
        $cliVer = "$(@(& spicetify -v 2>$null) | Select-Object -Last 1)".Trim()
        Row ok 'Spicetify CLI' ('installed [' + $cliVer + ']')
    }

    $ini = Join-Path $cfgDir 'config-xpui.ini'
    if ($spVer -and ($cli -or $used) -and (Test-Path -LiteralPath $ini)) {
        $cfg = @{}
        $section = ''
        foreach ($l in [IO.File]::ReadAllLines($ini)) {
            if ($l -match '^\s*\[(.+?)\]') { $section = $Matches[1]; continue }
            if ($l -match '^\s*([^=;#\s][^=]*?)\s*=\s*(.*?)\s*$') {
                $cfg[$section + '.' + $Matches[1]] = $Matches[2]
                if (-not $cfg.ContainsKey($Matches[1])) { $cfg[$Matches[1]] = $Matches[2] }
            }
        }
        $sp = $cfg['spotify_path']
        $pp = $cfg['prefs_path']
        $badPath = ($sp -and -not (Test-Path -LiteralPath $sp)) -or ($pp -and -not (Test-Path -LiteralPath $pp))
        if ($badPath -and (Test-Path -LiteralPath (Join-Path $spDir 'prefs'))) {
            Row fix 'Spicetify config' 'points to a missing Spotify folder'; Need 'spiceconfig'
        }
        # A backup made for an older Spotify means Spotify updated itself and wiped Spicetify.
        # A matching backup without xpui means the user restored Spotify on purpose - leave that alone.
        $bver = [string]$cfg['Backup.version']
        if (Test-Path -LiteralPath (Join-Path $spDir 'Apps\xpui')) {
            Row ok 'Spicetify' 'applied'
        } elseif ($bver -and -not $bver.StartsWith($spVer)) {
            Row fix 'Spicetify' ('Spotify ' + $spVer + ' update removed it'); Need 'spiceapply'
        } else {
            Row info 'Spicetify' 'not applied'
        }
    }

    # ---------------- Steam & Millennium ----------------
    Section 'STEAM & MILLENNIUM'
    $steam = [string]$env:SWX_STEAM_DIR
    if (-not ($steam -and (Test-Path -LiteralPath (Join-Path $steam 'steam.exe')))) {
        Row info 'Steam' 'not installed'
    } else {
        Row ok 'Steam' 'installed'
        $loaderPath = Join-Path $steam 'wsock32.dll'
        $vi = if (Test-Path -LiteralPath $loaderPath) { (Get-Item -LiteralPath $loaderPath).VersionInfo } else { $null }
        $isMill = [bool]($vi -and $vi.ProductName -match 'Millennium')
        $hasCore = Test-Path -LiteralPath (Join-Path $steam 'millennium\lib\millennium.dll')
        if ($isMill -and $hasCore) {
            Row ok 'Millennium' ('installed [' + ([string]$vi.ProductVersion).Trim() + ']')
        } elseif ($isMill) {
            Row fix 'Millennium' 'program files are missing'; Need 'millennium'
        } elseif ($hasCore -and -not $vi) {
            Row fix 'Millennium' 'a Steam update removed its loader'; Need 'millennium'
        } elseif ($hasCore) {
            Row bad 'Millennium' 'wsock32.dll belongs to another mod'
        } else {
            Row info 'Millennium' 'not installed'
        }
    }

    # ---------------- Swarlex ----------------
    Section 'SWARLEX'
    $valid = @{ intro = @('on', 'off'); relaunch = @('ifopen', 'always', 'never'); admin = @('on', 'off'); autoupdate = @('on', 'off') }
    $badKeys = @()
    if (Test-Path -LiteralPath $env:SWX_SETTINGS) {
        foreach ($l in [IO.File]::ReadAllLines($env:SWX_SETTINGS)) {
            if (-not $l.Trim()) { continue }
            $kv = $l -split '=', 2
            $k = $kv[0].Trim().ToLower()
            if ($kv.Count -lt 2 -or -not $valid.ContainsKey($k) -or $valid[$k] -notcontains $kv[1]) { $badKeys += $kv[0].Trim() }
        }
    }
    if ($badKeys.Count -gt 0) { Row fix 'Settings' ('invalid: ' + ($badKeys -join ', ')); Need 'settings' }
    else { Row ok 'Settings' 'valid' }

    $old = (Get-Date).AddMinutes(-10)
    $left = @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'swarlex-*' -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^swarlex-(plugin|backup|restore)-|^swarlex-(vencord-dist|millennium)$' -and $_.LastWriteTime -lt $old })
    if ($left.Count -gt 0) {
        $size = 0L
        foreach ($d in $left) { $size += Get-FolderSize $d.FullName }
        Row fix 'Temp files' ([string]$left.Count + ' leftover folder(s), ' + (Format-Size $size)); Need 'temp'
    } else {
        Row ok 'Temp files' 'clean'
    }
    if ($env:IS_ADMIN -eq '1') { Row info 'Privilege' 'Administrator - apps reopen normally' }
    else { Row info 'Privilege' 'Standard - enough for every fix' }

    [IO.File]::WriteAllLines($env:SWX_REPAIR_FILE, [string[]]$fixes.ToArray())
} catch {
    Write-Host ''
    Say ('[x] The scan failed: ' + $_.Exception.Message) 'Red'
    exit 99
}

Write-Host ''
if ($script:fixable -eq 0 -and $script:manual -eq 0) {
    Say '[+] No problems found.' 'Green'
} elseif ($script:fixable -eq 0) {
    Say ('[!] Nothing to fix automatically - see the red [x] lines.') 'Yellow'
} else {
    Say ('[*] ' + $script:fixable + ' problem(s) can be fixed automatically.') 'Cyan'
    if ($script:manual -gt 0) { Say '    The red [x] lines need you - Repair cannot fix those.' 'DarkGray' }
}
exit ([Math]::Min($script:fixable, 98))
::SWX_PS_END
::SWX_PS_BEGIN WINGET_UPDATER
$ind = ' ' * [int]$env:SWX_PAD
$line = ([string][char]0x2500) * 64
$bar = ([string][char]0x2500) * 62
$chev = [char]0x203A
$dot = [char]0x25CF
$check = [char]0x2714

$protected = @('explorer', 'svchost', 'powershell', 'cmd', 'conhost', 'dwm', 'csrss', 'lsass', 'winlogon', 'system', 'idle', 'taskmgr', 'code', 'antigravity', 'devenv', 'services', 'spoolsv', 'runtimebroker', 'searchhost', 'startmenuexperiencehost', 'shellexperiencehost', 'textinputhost', 'applicationframehost', 'systemsettings')

function Format-Center([string]$text, [int]$width = 62) {
    $padTotal = $width - $text.Length
    if ($padTotal -lt 0) { return $text.Substring(0, $width) }
    $padLeft = [math]::Floor($padTotal / 2)
    $padRight = $padTotal - $padLeft
    return (' ' * $padLeft) + $text + (' ' * $padRight)
}

# Swarlex's own chain of parent processes (this PowerShell, cmd, the console host or Windows Terminal).
# Closing any of them would close Swarlex itself, so they are never treated as "running instances".
$selfChain = @()
try {
    $all = @{}
    Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction Stop | ForEach-Object { $all[[int]$_.ProcessId] = [int]$_.ParentProcessId }
    $cur = $PID
    for ($n = 0; $n -lt 12 -and $cur -and $all.ContainsKey($cur); $n++) { $selfChain += $cur; $cur = $all[$cur] }
} catch { $selfChain = @($PID) }

# Apps that host this very window: updating them closes Swarlex, so they run in a separate window.
# Windows Terminal cannot be detected reliably: when a .bat is double-clicked, Windows hands the window
# to Terminal ("default terminal") without setting WT_SESSION and without Terminal being a parent
# process. So whenever Terminal itself is being updated while it is open, the separate window is used.
function Test-HostsSwarlex([string]$appId) {
    if ($appId -notmatch '^Microsoft\.WindowsTerminal(\.|$)') { return $false }
    if ($env:WT_SESSION) { return $true }
    return [bool](Get-Process -Name WindowsTerminal, OpenConsole -ErrorAction SilentlyContinue)
}

function Start-DetachedUpgrade($app) {
    # A classic console window (conhost) is not part of Windows Terminal, so it survives the update;
    # when winget is done it reopens Swarlex, which lands in the freshly updated Terminal again.
    $script = Join-Path $env:TEMP 'swarlex-selfupdate.cmd'
    $lines = @(
        '@echo off',
        'chcp 65001 >nul',
        ('title Swarlex - updating ' + $app.Name),
        'echo.',
        ('echo   Updating ' + $app.Name + ' - Swarlex reopens when it is done.'),
        'echo.',
        ('winget upgrade --id ' + $app.Id + ' -e --accept-package-agreements --accept-source-agreements --disable-interactivity'),
        'echo.',
        'ping -n 3 127.0.0.1 >nul',
        ('start "" cmd /d /c ""' + $env:SWX_SELF + '""'),
        '(goto) 2>nul & del "%~f0"'
    )
    [IO.File]::WriteAllText($script, ($lines -join "`r`n") + "`r`n")
    Write-Log 'INFO' ('Updating ' + $app.Name + ' in a separate window - Swarlex reopens afterwards')
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList ('cmd.exe /d /c "' + $script + '"')
}

# Keeps a line from wrapping back to the left edge of the window: web addresses shrink to their file
# name, and whatever is still wider than the window is cut with "~". Arg 2 = columns used before the text.
function Format-Fit([string]$text, [int]$lead) {
    # Room left on this line of the window (cut only what would really wrap), at least the card width
    $max = 58
    try { $max = [Math]::Max(58, [Console]::WindowWidth - $ind.Length - $lead - 1) } catch { }
    $text = [regex]::Replace($text, 'https?://\S+', { param($m) @($m.Value -split '[/?#]' | Where-Object { $_ })[-1] })
    if ($text.Length -gt $max) { $text = $text.Substring(0, $max - 1) + '~' }
    return $text
}

function Get-AppProcesses([string]$appName, [string]$appId) {
    $cleanName = ($appName -replace '[^\w]', '').ToLower()
    $idParts = $appId -split '\.'
    $idLeaf = ($idParts[-1] -replace '[^\w]', '').ToLower()
    $idRoot = ($idParts[0] -replace '[^\w]', '').ToLower()
    
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $pName = $_.ProcessName.ToLower()
        if ($protected -contains $pName) { return $false }
        if ($selfChain -contains $_.Id) { return $false }
        if (@('windowsterminal', 'openconsole') -contains $pName -and -not ($appId -match '^Microsoft\.WindowsTerminal')) { return $false }
        return ($pName -eq $cleanName -or $pName -eq $idLeaf -or $pName -eq $idRoot -or ($cleanName.Length -ge 4 -and $pName.StartsWith($cleanName)))
    }
    return @($procs)
}

function Get-WingetUpdates {
    $raw = & winget.exe upgrade 2>&1
    $lines = @($raw | ForEach-Object { "$_" })
    $dashIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-{10,}') { $dashIdx = $i; break }
    }
    $items = @()
    if ($dashIdx -gt 0) {
        $header = $lines[$dashIdx - 1]
        $posId = $header.IndexOf('Id')
        $posVer = $header.IndexOf('Version')
        $posAvail = $header.IndexOf('Available')
        $posSrc = $header.IndexOf('Source')
        
        for ($i = $dashIdx + 1; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if (-not $l -or $l -match '^\d+\s+upgrade' -or $l -match 'package\(s\)') { continue }
            if ($l.Length -gt $posAvail) {
                $name = $l.Substring(0, [Math]::Min($l.Length, $posId)).Trim()
                $id = $l.Substring($posId, [Math]::Min($l.Length - $posId, $posVer - $posId)).Trim()
                $ver = $l.Substring($posVer, [Math]::Min($l.Length - $posVer, $posAvail - $posVer)).Trim()
                $avail = if ($posSrc -gt 0 -and $l.Length -gt $posSrc) {
                    $l.Substring($posAvail, $posSrc - $posAvail).Trim()
                } else {
                    $l.Substring($posAvail).Trim()
                }
                if ($name -and $id -and $avail -and $avail -ne 'Unknown' -and $avail -ne $ver) {
                    $items += [pscustomobject]@{
                        Name = $name
                        Id = $id
                        Version = if ($ver -eq 'Unknown' -or -not $ver) { 'Current' } else { $ver }
                        Available = $avail
                    }
                }
            }
        }
    }
    return ,$items
}

$statusMsg = $null
$statusColor = 'DarkGray'

while ($true) {
    $items = Get-WingetUpdates
    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
    Write-Host (Format-Center 'A P P   U P D A T E R') -ForegroundColor White -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
    Write-Host (Format-Center 'Windows Package Manager (Winget)') -ForegroundColor DarkGray -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Cyan
    Write-Host ''

    $statusText = if ($items.Count -eq 0) { 'Up to date' } elseif ($items.Count -eq 1) { '1 Update' } else { ($items.Count.ToString() + ' Updates') }
    $col1 = ('  ' + $dot + ' Status    : ' + $statusText).PadRight(34)
    $col2 = ($dot + ' Manager   : Winget').PadRight(30)
    Write-Host ($ind + $col1 + $col2) -ForegroundColor White
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''

    if ($items.Count -eq 0) {
        if ($statusMsg) {
            Write-Host ($ind + '  ' + $statusMsg) -ForegroundColor $statusColor
            Write-Host ''
            $statusMsg = $null
        }
        Write-Host ($ind + '  [+] All installed applications are currently up to date!') -ForegroundColor Green
        Write-Host ''
        Write-Host ($ind + '  [R]  Refresh              Scan for updates again') -ForegroundColor White
        Write-Host ''
        Write-Host ($ind + '  [0]  Back                 Return to Main Menu') -ForegroundColor White
        Write-Host ''
        Write-Host ($ind + $line) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ($ind + '  ' + $chev + ' ') -ForegroundColor Cyan -NoNewline
        Write-Host 'Select an option [0/R]: ' -ForegroundColor White -NoNewline
        $in = [Console]::ReadLine()
        if ($null -eq $in) { break }
        $in = $in.Trim()
        if (-not $in -or $in -eq '0' -or $in -ieq 'b' -or $in -ieq 'back' -or $in -ieq 'q' -or $in -ieq 'exit') { break }
        if ($in -ieq 'r' -or $in -ieq 'refresh') {
            Clear-Host
            Write-Host ''
            Write-Host ''
            Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Cyan
            Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
            Write-Host (Format-Center 'A P P   U P D A T E R') -ForegroundColor White -NoNewline
            Write-Host ([char]0x2502) -ForegroundColor Cyan
            Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
            Write-Host (Format-Center 'Windows Package Manager (Winget)') -ForegroundColor DarkGray -NoNewline
            Write-Host ([char]0x2502) -ForegroundColor Cyan
            Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Cyan
            Write-Host ''
            Write-Host ($ind + '  [*] Scanning for application updates via Winget...') -ForegroundColor Cyan
            continue
        }
        continue
    }

    $hasSpotify = $false
    for ($i = 0; $i -lt $items.Count; $i++) {
        $app = $items[$i]
        if ($app.Id -eq 'Spotify.Spotify') { $hasSpotify = $true }
        
        $numStr = '[' + ($i + 1) + ']'
        $numStr = $numStr.PadRight(5)
        
        $nameStr = $app.Name
        if ($nameStr.Length -gt 18) { $nameStr = $nameStr.Substring(0, 16) + '..' }
        $nameStr = $nameStr.PadRight(19)
        
        $v1 = $app.Version -replace '(\.g|\+|-sha)[a-f0-9]+.*$', ''
        if ($v1.Length -gt 14) { $v1 = $v1.Substring(0, 12) + '..' }
        $v1 = $v1.PadLeft(14)
        
        $v2 = $app.Available -replace '(\.g|\+|-sha)[a-f0-9]+.*$', ''
        if ($v2.Length -gt 14) { $v2 = $v2.Substring(0, 12) + '..' }
        $v2 = $v2.PadRight(14)

        Write-Host ($ind + '  ') -NoNewline
        Write-Host $numStr -ForegroundColor Cyan -NoNewline
        Write-Host $nameStr -ForegroundColor White -NoNewline
        Write-Host $v1 -ForegroundColor DarkGray -NoNewline
        Write-Host (' ' + $chev + ' ') -ForegroundColor Cyan -NoNewline
        Write-Host $v2 -ForegroundColor Green
    }

    Write-Host ''
    if ($statusMsg) {
        Write-Host ($ind + '  ' + $statusMsg) -ForegroundColor $statusColor
        Write-Host ''
        $statusMsg = $null
    }
    if ($hasSpotify) {
        Write-Host ($ind + '  ' + $dot + ' Notice: If Spotify is updated, re-apply Spicetify from Spotify menu.') -ForegroundColor Yellow
        Write-Host ''
    }
    Write-Host ($ind + '  [A]  Upgrade All          Upgrade all available applications') -ForegroundColor White
    Write-Host ($ind + '  [R]  Refresh              Scan for updates again') -ForegroundColor White
    Write-Host ''
    Write-Host ($ind + '  [0]  Back                 Return to Main Menu') -ForegroundColor White
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ($ind + '  ' + $chev + ' ') -ForegroundColor Cyan -NoNewline
    Write-Host 'Select app(s) to upgrade (e.g. 1 or A): ' -ForegroundColor White -NoNewline

    $in = [Console]::ReadLine()
    if ($null -eq $in) { break }
    $in = $in.Trim()
    if (-not $in -or $in -eq '0' -or $in -ieq 'b' -or $in -ieq 'back' -or $in -ieq 'q' -or $in -ieq 'exit') { break }
    if ($in -ieq 'r' -or $in -ieq 'refresh') {
        Clear-Host
        Write-Host ''
        Write-Host ''
        Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Cyan
        Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
        Write-Host (Format-Center 'A P P   U P D A T E R') -ForegroundColor White -NoNewline
        Write-Host ([char]0x2502) -ForegroundColor Cyan
        Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
        Write-Host (Format-Center 'Windows Package Manager (Winget)') -ForegroundColor DarkGray -NoNewline
        Write-Host ([char]0x2502) -ForegroundColor Cyan
        Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Cyan
        Write-Host ''
        Write-Host ($ind + '  [*] Scanning for application updates via Winget...') -ForegroundColor Cyan
        continue
    }

    $toUpgrade = @()
    if ($in -ieq 'a' -or $in -ieq 'all') {
        $toUpgrade = $items
    } else {
        $tokens = $in -split '[,\s]+'
        $selIndices = @()
        foreach ($tok in $tokens) {
            if ($tok -match '^(\d+)-(\d+)$') {
                $start = [int]$matches[1]
                $end = [int]$matches[2]
                for ($k = $start; $k -le $end; $k++) {
                    if ($k -ge 1 -and $k -le $items.Count) { $selIndices += ($k - 1) }
                }
            } elseif ($tok -match '^\d+$') {
                $val = [int]$tok
                if ($val -ge 1 -and $val -le $items.Count) { $selIndices += ($val - 1) }
            }
        }
        $selIndices = @($selIndices | Select-Object -Unique)
        foreach ($idx in $selIndices) {
            $toUpgrade += $items[$idx]
        }
    }

    if ($toUpgrade.Count -eq 0) {
        $statusMsg = '[!] Invalid selection. Enter app number, list (e.g. 1,2), or A for all.'
        $statusColor = 'Yellow'
        continue
    }

    Clear-Host
    Write-Host ''
    Write-Host ''
    Write-Host ($ind + [char]0x256D + $bar + [char]0x256E) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
    Write-Host (Format-Center 'A P P   U P D A T E R') -ForegroundColor White -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2502) -ForegroundColor Cyan -NoNewline
    Write-Host (Format-Center 'Installing Application Updates') -ForegroundColor DarkGray -NoNewline
    Write-Host ([char]0x2502) -ForegroundColor Cyan
    Write-Host ($ind + [char]0x2570 + $bar + [char]0x256F) -ForegroundColor Cyan
    Write-Host ''
    $col1 = ('  ' + $dot + ' Target    : ' + $toUpgrade.Count + $(if ($toUpgrade.Count -eq 1) { ' app' } else { ' apps' })).PadRight(34)
    $col2 = ($dot + ' Status    : In Progress').PadRight(30)
    Write-Host ($ind + $col1 + $col2) -ForegroundColor White
    Write-Host ''
    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''

    $successfulUpdates = @()
    $failedUpdates = @()
    # Whatever hosts this window is updated last, after everything else is done
    $toUpgrade = @(@($toUpgrade | Where-Object { -not (Test-HostsSwarlex $_.Id) }) + @($toUpgrade | Where-Object { Test-HostsSwarlex $_.Id }))

    foreach ($targetApp in $toUpgrade) {
        Write-Host ($ind + '  ' + (Format-Fit ($chev + ' Upgrading ' + $targetApp.Name + ' [' + $targetApp.Id + ']...') 2)) -ForegroundColor Cyan

        if (Test-HostsSwarlex $targetApp.Id) {
            Write-Host ($ind + '    [!] Swarlex runs inside ' + $targetApp.Name + ', which has to close for this update.') -ForegroundColor Yellow
            Write-Host ($ind + '    [*] The update continues in a separate window, this one closes now and') -ForegroundColor Cyan
            Write-Host ($ind + '        Swarlex reopens by itself when the update is done.') -ForegroundColor Cyan
            Write-History 'Winget Upgrade' ($targetApp.Name + ' [' + $targetApp.Id + '] - handed to a separate window')
            Start-DetachedUpgrade $targetApp
            Start-Sleep -Seconds 3
            # 42 tells the batch side to close this window - the updater window reopens Swarlex,
            # so staying open would leave two copies running
            exit 42
        }
        
        $running = Get-AppProcesses $targetApp.Name $targetApp.Id
        if ($running.Count -gt 0) {
            Write-Host ($ind + '    [!] Closing running instances of ' + $targetApp.Name + '...') -ForegroundColor Yellow
            foreach ($p in $running) {
                try { $p.CloseMainWindow() | Out-Null } catch {}
            }
            Start-Sleep -Milliseconds 600
            $stillRunning = Get-AppProcesses $targetApp.Name $targetApp.Id
            if ($stillRunning.Count -gt 0) {
                foreach ($p in $stillRunning) {
                    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
                }
                Start-Sleep -Milliseconds 600
            }
        }
        
        # Through a file, not a pipe: installers that start their app afterwards (Spotify does) would
        # otherwise keep the pipe open and the updater would wait until that app is closed
        $procExit = Invoke-Tool 'winget' ('upgrade --id ' + $targetApp.Id + ' -e --accept-package-agreements --accept-source-agreements --disable-interactivity')
        
        if ($procExit -eq 0) {
            Write-Host ($ind + '  [+] ' + $targetApp.Name + ' successfully updated.') -ForegroundColor Green
            $successfulUpdates += $targetApp.Name
            if (Get-Command Write-History -ErrorAction SilentlyContinue) {
                Write-History 'Winget Upgrade' ($targetApp.Name + ' [' + $targetApp.Id + ']')
            }
        } else {
            Write-Host ($ind + '  [x] Failed to update ' + $targetApp.Name + ' (Exit code: ' + $procExit + ')') -ForegroundColor Red
            Write-Log 'ERROR' ('winget could not upgrade ' + $targetApp.Name + ' [' + $targetApp.Id + '], exit code ' + $procExit)
            $failedUpdates += $targetApp.Name
        }
        Write-Host ''
    }

    Write-Host ($ind + $line) -ForegroundColor DarkGray
    Write-Host ''
    if ($successfulUpdates.Count -gt 0 -and $failedUpdates.Count -eq 0) {
        Write-Host ($ind + '  [+] ' + $successfulUpdates.Count + ' of ' + $toUpgrade.Count + $(if ($toUpgrade.Count -eq 1) { ' app' } else { ' apps' }) + ' successfully updated.') -ForegroundColor Green
        $statusMsg = '[+] Upgraded ' + ($successfulUpdates -join ', ')
        $statusColor = 'Green'
        if ($successfulUpdates -contains 'Spotify' -or ($toUpgrade | Where-Object { $_.Id -eq 'Spotify.Spotify' -and $successfulUpdates -contains $_.Name })) {
            Write-Host ''
            Write-Host ($ind + '  [!] Tip: Spotify was updated. Re-apply it from Spotify > [1] Apply Spicetify.') -ForegroundColor Cyan
        }
    } elseif ($successfulUpdates.Count -gt 0 -and $failedUpdates.Count -gt 0) {
        Write-Host ($ind + '  [!] Partial update: ' + ($successfulUpdates -join ', ') + ' succeeded.') -ForegroundColor Green
        Write-Host ($ind + '  [x] Failed: ' + ($failedUpdates -join ', ')) -ForegroundColor Red
        $statusMsg = '[!] Partial update (' + $successfulUpdates.Count + ' succeeded, ' + $failedUpdates.Count + ' failed)'
        $statusColor = 'Yellow'
    } else {
        Write-Host ($ind + '  [x] Update process failed for: ' + ($failedUpdates -join ', ')) -ForegroundColor Red
        $statusMsg = '[x] Failed to upgrade selected app(s)'
        $statusColor = 'Red'
    }
    Write-Host ''
    Write-Host ($ind + '  Press Enter to continue...') -ForegroundColor DarkGray
    [Console]::ReadLine() | Out-Null
}
exit 0
::SWX_PS_END



