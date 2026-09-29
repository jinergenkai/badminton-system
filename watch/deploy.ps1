# Band / phone helper.
#
#   .\deploy.ps1                 push the release .rpk to the phone (default)
#   .\deploy.ps1 -Clean          kill every app on the phone (fixes lag)
#   .\deploy.ps1 -StopMiFitness  stop Mi Fitness so Notify can install on the band
#
# Switches combine, e.g.  .\deploy.ps1 -StopMiFitness   then install from Notify.

param(
    [switch]$Clean,
    [switch]$StopMiFitness,
    [switch]$Push
)

$Rpk = 'bandcounter-watch/dist/com.hung.bandcounter.release.1.0.0.rpk'

# Mi Fitness has shipped under both names; stopping a missing one is harmless.
$MiFitness = @('com.mi.health', 'com.xiaomi.wearable')

if (-not ($Clean -or $StopMiFitness)) { $Push = $true }

if ($Clean) {
    Write-Host '== Killing background processes =='
    adb shell am kill-all

    # kill-all only reaches cached background processes. Force-stop every
    # user-installed app too, except the keyboard (killing it just makes it
    # restart on the next text field).
    $ime = (adb shell settings get secure default_input_method) -replace '/.*', ''
    $pkgs = adb shell pm list packages -3 | ForEach-Object { ($_ -replace '^package:', '').Trim() }
    foreach ($p in $pkgs) {
        if (-not $p -or $p -eq $ime.Trim()) { continue }
        adb shell am force-stop $p
        Write-Host "  stopped $p"
    }
    Write-Host 'Done. Mi Fitness was stopped too: redo the ritual'
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
