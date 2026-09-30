# Band / phone helper.
#
#   .\deploy.ps1                 push the release .rpk to the phone (default)
#   .\deploy.ps1 -Clean          kill every app on the phone (fixes lag now)
#   .\deploy.ps1 -Slim           one-time: disable Google bloat, cap background
#   .\deploy.ps1 -Unslim         undo everything -Slim did
#   .\deploy.ps1 -Mem            show RAM and the biggest processes
#   .\deploy.ps1 -StopMiFitness  stop Mi Fitness so Notify can install on the band
#   .\deploy.ps1 -Dev            the whole dev loop, guided (README section 4)
#   .\deploy.ps1 -Court          one-time, at home: turn off apps the court
#                                tablet does not need (kept across reboots)
#   .\deploy.ps1 -Uncourt        undo -Court

param(
    [switch]$Clean,
    [switch]$Slim,
    [switch]$Unslim,
    [switch]$Mem,
    [switch]$StopMiFitness,
    [switch]$Push,
    [switch]$Dev,
    [switch]$Court,
    [switch]$Uncourt
)

$Rpk = 'bandcounter-watch/dist/com.hung.bandcounter.release.1.0.0.rpk'

# Mi Fitness has shipped under both names; stopping a missing one is harmless.
# The modded build on the dev phone is com.xiaomi.wearable.
$MiFitness = @('com.mi.health', 'com.xiaomi.wearable')
$Notify = 'com.mc.xiaomi1'   # Notify for Xiaomi

function Start-App($pkg) {
    adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
}

function Stop-MiFitness {
    foreach ($p in $MiFitness) {
        adb shell am force-stop $p
        Write-Host "  stopped $p"
    }
}

# System apps that respawn and eat RAM. Force-stopped by -Clean.
$Hogs = @(
    'com.android.vending',                   # Play Store
    'com.android.chrome',
    'com.google.android.googlequicksearchbox',
    'com.google.android.apps.wellbeing'
)

# Disabled by -Slim, re-enabled by -Unslim. Chrome is deliberately NOT here:
# on Android 10+ it can be the WebView provider, and disabling it breaks
# every in-app web view. It is only force-stopped.
$Disable = @(
    'com.google.android.googlequicksearchbox',
    'com.google.android.apps.wellbeing',
    'com.android.vending'
)

# Fast on a struggling phone: /proc/meminfo and ps answer at once, where
# 'dumpsys meminfo' walks every process and can take a minute under memory
# pressure - which is exactly when -Clean is needed.
function Show-Mem {
    Write-Host '== Memory (kB) =='
    adb shell "grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo"
    Write-Host '-- biggest processes (RSS kB) --'
    adb shell "ps -A -o RSS,NAME | sort -rn | head -10"
    Write-Host '-- CPU now --'
    adb shell "top -b -n 1 -m 6 | tail -6"
}

# -Dev runs Clean itself, at the right point in the sequence.
if ($Dev) { $Clean = $false; $Push = $false }
if (-not ($Clean -or $Slim -or $Unslim -or $Mem -or $StopMiFitness -or $Dev -or $Court -or $Uncourt)) { $Push = $true }

if ($Mem) { Show-Mem }

if ($Slim) {
    Write-Host '== Slim (persistent until -Unslim) =='
    foreach ($p in $Disable) {
        adb shell pm disable-user --user 0 $p
    }
    adb shell cmd appops set com.android.vending RUN_IN_BACKGROUND ignore
    # Caps *cached* background processes. Watch for it: if the band link
    # starts dropping after -Slim, this is the first suspect (Mi Fitness's
    # service is what carries the link) - run -Unslim.
    adb shell settings put global limit_background_processes 3
    Write-Host 'Play Store is disabled: run -Unslim before installing/updating apps.'
    Write-Host 'If the band link gets flaky after this, run -Unslim.'
}

if ($Unslim) {
    Write-Host '== Unslim =='
    foreach ($p in $Disable) {
        adb shell pm enable $p
    }
    adb shell cmd appops set com.android.vending RUN_IN_BACKGROUND allow
    adb shell settings delete global limit_background_processes
}

# ── Court tablet: run once at home, it lasts across reboots ─────────────
# Nothing here uninstalls or deletes data: every step is undone by -Uncourt.
#
# Off: cannot run at all, icon hidden (pm disable-user). Asked to be removed;
# uninstalling would also delete their data, so they are only switched off —
# uninstall them from Settings if they are really not wanted.
$CourtOff = @(
    'com.zing.zalo',
    'com.samsung.android.app.watchmanager',  # Galaxy Wearable: scans Bluetooth
    'com.openai.chatgpt',
    'com.chess',
    'com.englishscore'
)
# No background: still open normally, but cannot start or keep running on
# their own (after boot, for push, sync...).
$CourtNoBackground = @(
    'com.ss.android.ugc.trill',              # TikTok
    'com.wireguard.android',                 # a running VPN costs CPU per packet
    'com.flyersoft.moonreader',
    'com.foxit.mobile.pdf.lite',
    'com.microsoft.office.excel',
    'com.google.android.apps.docs.editors.sheets',
    'com.microsoft.rdc.androidx',
    'com.server.auditor.ssh.client',         # Termius
    'com.termux',
    'com.nerversoft.ark.recode',
    'com.teclast.teclastuserfeedback',
    'com.watchfun.classearjoy',
    'com.csdcorp.speech_to_text_example',
    'com.example.chicki_buddy',
    'com.example.jar_talk',
    'bds.guland.com',
    'bds.guland.vietnam.com',
    'com.google.android.contactkeys'
)
# Never touched: this app, Mi Fitness (carries band -> phone), Notify, the
# Touch Lock overlay used on court, the keyboard and TTS.

if ($Court) {
    Write-Host '== Court: off =='
    $cmd = ($CourtOff | ForEach-Object { "pm disable-user --user 0 $_ >/dev/null 2>&1 && echo '  off  $_'" }) -join '; '
    adb shell $cmd
    Write-Host '== Court: no background =='
    $cmd = ($CourtNoBackground | ForEach-Object {
        "cmd appops set $_ RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1 && " +
        "cmd appops set $_ RUN_IN_BACKGROUND ignore >/dev/null 2>&1; " +
        "am set-standby-bucket $_ restricted >/dev/null 2>&1; am force-stop $_; echo '  bg   $_'"
    }) -join '; '
    adb shell $cmd
    Write-Host 'Done. Lasts across reboots; .\deploy.ps1 -Uncourt undoes it.'
}

if ($Uncourt) {
    Write-Host '== Uncourt =='
    $cmd = ($CourtOff | ForEach-Object { "pm enable $_ >/dev/null 2>&1 && echo '  on   $_'" }) -join '; '
    adb shell $cmd
    $cmd = ($CourtNoBackground | ForEach-Object {
        "cmd appops set $_ RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1; " +
        "cmd appops set $_ RUN_IN_BACKGROUND allow >/dev/null 2>&1; " +
        "am set-standby-bucket $_ active >/dev/null 2>&1; echo '  bg ok $_'"
    }) -join '; '
    adb shell $cmd
}

function Invoke-Clean {
    Show-Mem

    Write-Host '== Stopping apps =='
    # Every user-installed app and the system hogs, except the keyboard
    # (killing it just makes it restart on the next text field). One adb
    # shell for all of it: one connection per app crawled on a lagging phone.
    $ime = ((adb shell settings get secure default_input_method) -replace '/.*', '').Trim()
    $pkgs = @($Hogs) + @(adb shell pm list packages -3 | ForEach-Object { ($_ -replace '^package:', '').Trim() })
    $pkgs = $pkgs | Where-Object { $_ -and $_ -ne $ime } | Sort-Object -Unique
    $script = ($pkgs | ForEach-Object { "am force-stop $_" }) -join '; '
    # kill-all last, so it also sweeps whatever the force-stops left cached.
    adb shell "$script; am kill-all"
    Write-Host "  stopped $($pkgs.Count) apps"

    Show-Mem
    Write-Host 'Mi Fitness was stopped too: redo the ritual'
    Write-Host '(Mi Fitness sync -> band app -> phone app) before playing.'
}

if ($Clean) { Invoke-Clean }

if ($StopMiFitness) {
    Write-Host '== Stopping Mi Fitness =='
    Stop-MiFitness
    Write-Host 'Now open Notify for Xiaomi and install the .rpk.'
}

if ($Push) {
    Write-Host '== Pushing band app =='
    adb push $Rpk /sdcard/Download/
}

# The dev loop that actually gets a new build onto the band. Order matters:
# Notify can only install while it holds the band, it only gets the band
# after Mi Fitness has synced (auth), and it only keeps it once Mi Fitness
# is out of the way.
if ($Dev) {
    Write-Host '== 1/6 Build band app (release) =='
    Push-Location bandcounter-watch
    npm run release
    $ok = $LASTEXITCODE -eq 0
    Pop-Location
    if (-not $ok -or -not (Test-Path $Rpk)) { Write-Host 'Build failed, stopping.'; exit 1 }

    Write-Host '== 2/6 Push .rpk to /sdcard/Download =='
    adb push $Rpk /sdcard/Download/

    Write-Host '== 3/6 Clean the phone =='
    Invoke-Clean

    Write-Host '== 4/6 Mi Fitness: sync the band =='
    Start-App 'com.xiaomi.wearable'
    Read-Host 'In Mi Fitness, pull to Sync until the band is connected, then press Enter'

    Write-Host '== 5/6 Notify: connect (leave Mi Fitness open behind it) =='
    Start-App $Notify
    Read-Host 'Wait until Notify shows the band connected, then press Enter'

    Write-Host '== 6/6 Stop Mi Fitness, then install =='
    Stop-MiFitness
    Write-Host 'In Notify: firmware / app install -> third-party app ->'
    Write-Host '  Download/com.hung.bandcounter.release.1.0.0.rpk'
    Write-Host 'After install: redo the ritual (Mi Fitness sync -> band app -> phone app).'
}
