# Band / phone helper.
#
#   .\deploy.ps1                 push the release .rpk to the phone (default)
#   .\deploy.ps1 -Clean          kill every app on the phone (fixes lag now)
#   .\deploy.ps1 -Slim           one-time: disable Google bloat, cap background
#   .\deploy.ps1 -Unslim         undo everything -Slim did
#   .\deploy.ps1 -Mem            show RAM and the biggest processes
#   .\deploy.ps1 -StopMiFitness  stop Mi Fitness so Notify can install on the band

param(
    [switch]$Clean,
    [switch]$Slim,
    [switch]$Unslim,
    [switch]$Mem,
    [switch]$StopMiFitness,
    [switch]$Push
)

$Rpk = 'bandcounter-watch/dist/com.hung.bandcounter.release.1.0.0.rpk'

# Mi Fitness has shipped under both names; stopping a missing one is harmless.
$MiFitness = @('com.mi.health', 'com.xiaomi.wearable')

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

function Show-Mem {
    Write-Host '== Memory =='
    adb shell "dumpsys meminfo | grep -E 'Total RAM|Free RAM|Used RAM'"
    Write-Host '-- biggest processes --'
    adb shell "dumpsys meminfo | grep -A 15 'by process' | head -17"
}

if (-not ($Clean -or $Slim -or $Unslim -or $Mem -or $StopMiFitness)) { $Push = $true }

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

if ($Clean) {
    Show-Mem

    Write-Host '== Stopping apps =='
    foreach ($p in $Hogs) { adb shell am force-stop $p }

    # Every user-installed app too, except the keyboard (killing it just
    # makes it restart on the next text field).
    $ime = ((adb shell settings get secure default_input_method) -replace '/.*', '').Trim()
    $pkgs = adb shell pm list packages -3 | ForEach-Object { ($_ -replace '^package:', '').Trim() }
    foreach ($p in $pkgs) {
        if (-not $p -or $p -eq $ime) { continue }
        adb shell am force-stop $p
        Write-Host "  stopped $p"
    }

    # Last, so it also sweeps whatever the force-stops left cached.
    adb shell am kill-all

    Show-Mem
    Write-Host 'Mi Fitness was stopped too: redo the ritual'
    Write-Host '(Mi Fitness sync -> band app -> phone app) before playing.'
}

if ($StopMiFitness) {
    Write-Host '== Stopping Mi Fitness =='
    foreach ($p in $MiFitness) {
        adb shell am force-stop $p
        Write-Host "  stopped $p"
    }
    Write-Host 'Now open Notify for Xiaomi and install the .rpk.'
}

if ($Push) {
    Write-Host '== Pushing band app =='
    adb push $Rpk /sdcard/Download/
}
