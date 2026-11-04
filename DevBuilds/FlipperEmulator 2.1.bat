@echo off
setlocal
title Flipper One Demo v2.1
rem Flipper One Demo - unofficial helper, v2.1
rem Adds experimental "real Flipper OS" mode via QEMU aarch64 emulation.
set "FLIP_BAT=%~f0"
set "FLIP_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Get-Content -LiteralPath $env:FLIP_BAT -Raw -Encoding UTF8; $i = $f.IndexOf('#PS1' + 'START'); Invoke-Expression $f.Substring($i)"
exit /b %errorlevel%
#PS1START
# =============================================================================
# Flipper One Demo - unofficial helper script (v2.1)
#
# NOT affiliated with or endorsed by Flipper Devices.
#
# v1.x: only extracts the FlipCTL *test* UI (fake-flipctl2) from the image.
# v2.1: keeps that as Option 1, and adds Option 2 - booting the REAL Flipper OS
#       kernel + initramfs inside QEMU (aarch64) on this PC. Experimental:
#       the image targets Rockchip RK3576 (ARM). Hardware is emulated only.
#       Real hardware (Wi-Fi, modem, battery, GPIO) will NOT work on a PC.
# =============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Version    = '2.1'
$Root       = Join-Path $env:LOCALAPPDATA 'FlipperOneDemo'
$Distro     = 'FlipperOne'
$Port       = 8899
$RealPort   = 8899
$Url        = "http://127.0.0.1:$Port/"
$ImageUrl   = 'https://dl-linux-images.flipp.dev/full-img/2407/debian-512-sige5-2407.img.zst'
$UbuntuBase = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/'
$NodeUrls   = @('https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-x64.tar.xz')
$DeviceUA   = 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/605.1.15 (KHTML, like Gecko) Cog/0.18.4 WPE'
$MenuDir    = Join-Path ([Environment]::GetFolderPath('Programs')) 'Flipper One Demo'
$RealRoot   = Join-Path $Root 'realos'
$QemuPidFile= Join-Path $Root 'qemu.pid'

$InstallScript = @'
#!/bin/bash
# Runs as root inside the private WSL distribution "FlipperOne".
set -Eeuo pipefail
ZST="${1:?Path to the .img.zst file is missing}"
NODE_TAR="${2:-}"
IMG="/var/tmp/flipper-os.img"
MNT="/mnt/flipimg"
LOOP=""
KPARTX=0
OFFLOOPS=()
PARTS=()
log()  { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }
die()  { echo "XX  $*" >&2; exit 1; }
cleanup() {
  set +e
  local d lp
  for d in $(find "$MNT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r); do
    umount "$d" 2>/dev/null || umount -l "$d" 2>/dev/null
  done
  for lp in "${OFFLOOPS[@]:-}"; do [ -n "$lp" ] && losetup -d "$lp" 2>/dev/null; done
  [ "$KPARTX" = 1 ] && [ -n "$LOOP" ] && kpartx -d "$LOOP" >/dev/null 2>&1
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rm -f "$IMG"
}
trap cleanup EXIT
log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y zstd btrfs-progs util-linux kpartx rsync xz-utils fdisk e2fsprogs squashfs-tools ca-certificates curl
if [ -n "$NODE_TAR" ] && [ -f "$NODE_TAR" ]; then
  log "Setting up Node.js"
  mkdir -p /opt/node
  tar -xJf "$NODE_TAR" -C /opt/node --strip-components=1
else
  log "Installing Node.js via apt"
  apt-get install -y nodejs
  mkdir -p /opt/node/bin
  ln -sf "$(command -v node)" /opt/node/bin/node
fi
/opt/node/bin/node --version
log "Unpacking image (needs about 6 GB temporarily)"
zstd -d -f --long=31 "$ZST" -o "$IMG"
attach_by_offset() {
  local ss line start size lp
  ss="$(sfdisk -d "$IMG" 2>/dev/null | awk -F': *' '/^sector-size:/{print $2}' || true)"
  ss="${ss:-512}"
  while IFS= read -r line; do
    start="$(sed -n 's/.*start= *\([0-9][0-9]*\),.*/\1/p' <<<"$line")"
    size="$(sed -n 's/.*size= *\([0-9][0-9]*\),.*/\1/p' <<<"$line")"
    { [ -n "$start" ] && [ -n "$size" ] && [ "$size" -gt 0 ]; } || continue
    lp="$(losetup -f --show -o $((start*ss)) --sizelimit $((size*ss)) "$IMG")" || continue
    OFFLOOPS+=("$lp"); PARTS+=("$lp")
  done < <(sfdisk -d "$IMG" 2>/dev/null | grep -E '^[^ ]+ *: *start=' || true)
}
log "Mounting image"
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$IMG")" || die "Loop devices are not available. Run 'wsl --update' in PowerShell and try again."
sleep 1
while IFS= read -r p; do [ -n "$p" ] && PARTS+=("$p"); done < <(ls -1 "${LOOP}"p* 2>/dev/null | sort -V || true)
if [ "${#PARTS[@]}" -eq 0 ]; then
  kpartx -avs "$LOOP" >/dev/null 2>&1 && KPARTX=1 || true
  while IFS= read -r p; do [ -n "$p" ] && PARTS+=("$p"); done < <(ls -1 /dev/mapper/"$(basename "$LOOP")"p* 2>/dev/null | sort -V || true)
fi
[ "${#PARTS[@]}" -gt 0 ] || attach_by_offset
[ "${#PARTS[@]}" -gt 0 ] || PARTS=("$LOOP")
log "Partitions: ${PARTS[*]}"
n=0
for p in "${PARTS[@]}"; do
  n=$((n+1))
  t="$(blkid -o value -s TYPE "$p" 2>/dev/null || true)"
  mkdir -p "$MNT/p$n"
  case "$t" in
    btrfs) mount -o ro,subvolid=5 "$p" "$MNT/p$n" 2>/dev/null || mount -o ro "$p" "$MNT/p$n" 2>/dev/null || rmdir "$MNT/p$n" ;;
    ext2|ext3|ext4|xfs|f2fs) mount -o ro "$p" "$MNT/p$n" 2>/dev/null || rmdir "$MNT/p$n" ;;
    *) rmdir "$MNT/p$n" ;;
  esac
done
log "Looking for the FlipCTL test folder in the image"
SRC=""
while IFS= read -r d; do
  case "$d" in *stock-snapshots*) continue ;; esac
  if [ -f "$d/server.js" ]; then SRC="$(dirname "$d")"; break; fi
done < <(find "$MNT" -maxdepth 6 -type d -name fake-flipctl2 2>/dev/null | sort)
if [ -z "$SRC" ]; then
  while IFS= read -r d; do
    if [ -f "$d/server.js" ]; then SRC="$(dirname "$d")"; break; fi
  done < <(find "$MNT" -maxdepth 6 -type d -name fake-flipctl2 2>/dev/null | sort)
fi
[ -n "$SRC" ] || die "No fake-flipctl2 folder found in the image. It may be a different image version."
log "Found: $SRC"
log "Copying to /flipperone-testing"
mkdir -p /flipperone-testing
rsync -a --delete "$SRC"/ /flipperone-testing/
ln -sfn /flipperone-testing/fake-flipctl2 /flipperone-testing/active-flipctl
[ -f /flipperone-testing/fake-flipctl2/server.js ] || die "server.js is missing after copying."
log "Quick test: starting the server"
cd /flipperone-testing/fake-flipctl2
( timeout 10 /opt/node/bin/node server.js >/tmp/smoke.log 2>&1 & )
ok=0
for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  if curl -fsS http://127.0.0.1:8899/api/version >/dev/null 2>&1; then ok=1; break; fi
done
if [ "$ok" = 1 ]; then log "Server responds."; else warn "Quick test: no response. Output:"; tail -n 20 /tmp/smoke.log || true; fi
log "Setup inside the Linux environment finished."
'@

function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Pause-Close { Read-Host 'Press Enter to close' | Out-Null }
function Fail($m) { Write-Host "XX  $m" -ForegroundColor Red; Pause-Close; exit 1 }

function Get-File($urls, $dest, $optional = $false) {
    if (Test-Path $dest) { return $true }
    $first = $true
    foreach ($u in @($urls)) {
        if (-not $first) { Remove-Item "$dest.part" -Force -ErrorAction SilentlyContinue }
        $first = $false
        if ((Test-Path "$dest.part") -and ((Get-Item "$dest.part").Length -eq 0)) { Remove-Item "$dest.part" -Force }
        Say "Downloading: $u"
        & curl.exe -L --fail --retry 3 --retry-delay 2 -C - -o "$dest.part" $u
        if ($LASTEXITCODE -eq 0 -and (Test-Path "$dest.part")) {
            Move-Item "$dest.part" $dest -Force
            return $true
        }
        Warn "Failed: $u"
    }
    if ($optional) { return $false }
    Fail ("Download failed: " + (@($urls) -join ' , '))
}

function Resolve-UbuntuUrls {
    $urls = New-Object System.Collections.ArrayList
    [void]$urls.Add($UbuntuBase + 'current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz')
    try {
        $idx = (Invoke-WebRequest -Uri $UbuntuBase -UseBasicParsing -TimeoutSec 20).Content
        $dates = [regex]::Matches($idx, 'href="(\d{8})/"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Descending
        foreach ($d in ($dates | Select-Object -First 3)) {
            $sub = (Invoke-WebRequest -Uri ($UbuntuBase + $d + '/') -UseBasicParsing -TimeoutSec 20).Content
            $names = [regex]::Matches($sub, 'href="(ubuntu-noble-wsl-amd64-[A-Za-z0-9._-]*\.rootfs\.tar\.gz)"') | ForEach-Object { $_.Groups[1].Value }
            $pick = $names | Where-Object { $_ -like '*-wsl.rootfs.tar.gz' } | Select-Object -First 1
            if (-not $pick) { $pick = $names | Select-Object -First 1 }
            if ($pick) { [void]$urls.Add($UbuntuBase + $d + '/' + $pick) }
        }
    } catch { }
    [void]$urls.Add($UbuntuBase + '20240423/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz')
    return , $urls.ToArray()
}

function Test-WslReady {
    try { & wsl.exe --status *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Test-Distro {
    $old = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $l = (& wsl.exe -l -q) | Out-String
    } finally { [Console]::OutputEncoding = $old }
    $l = $l -replace "`0", ''
    $names = ($l -split "`r?`n") | ForEach-Object { $_.Trim() }
    return ($names -contains $Distro)
}

function ConvertTo-WslPath($p) {
    $d = $p.Substring(0, 1).ToLower()
    return '/mnt/' + $d + ($p.Substring(2) -replace '\\', '/')
}

$script:LastErr = ''
function Test-Server {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/version" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { return $true }
        $script:LastErr = 'HTTP ' + $r.StatusCode
    } catch { $script:LastErr = $_.Exception.Message }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        $conn = ($ok -and $c.Connected)
        $c.Close()
        if ($conn) { return $true }
    } catch { }
    return $false
}

function Find-Browser {
    $pf86 = ${env:ProgramFiles(x86)}
    $c = @(
        "$pf86\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$pf86\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Get-DeviceProcs {
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*FlipperOneDemo*device-profile*' }
}

function New-DemoShortcuts {
    try {
        $self = "$Root\Flipper-One-Demo.bat"
        if ($env:FLIP_BAT -and ($env:FLIP_BAT -ne $self)) { Copy-Item -LiteralPath $env:FLIP_BAT -Destination $self -Force }
        if (-not (Test-Path $self)) { return }
        New-Item -ItemType Directory -Force -Path $MenuDir | Out-Null
        $ws = New-Object -ComObject WScript.Shell
        foreach ($item in @(@('Start Flipper One', 'start'), @('Stop Flipper One', 'stop'))) {
            $lnk = $ws.CreateShortcut((Join-Path $MenuDir ($item[0] + '.lnk')))
            $lnk.TargetPath = $self
            $lnk.Arguments = $item[1]
            $lnk.WorkingDirectory = $Root
            $lnk.Save()
        }
    } catch { Warn 'Could not create the Start menu shortcuts.' }
}

function Install-All {
    New-Item -ItemType Directory -Force -Path "$Root\dl", "$Root\distro" | Out-Null
    if (-not (Test-WslReady)) {
        Warn 'WSL (Windows Subsystem for Linux) is not set up yet.'
        Say 'Starting the WSL installation (please confirm the administrator prompt) ...'
        try {
            Start-Process wsl.exe -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait
        } catch {
            Fail 'WSL could not be installed. Please run "wsl --install --no-distribution" in an administrator PowerShell.'
        }
        Write-Host ''
        Write-Host 'WSL has been set up. Please RESTART your PC, then double-click this file again.' -ForegroundColor Green
        Pause-Close
        exit 0
    }
    if (-not (Test-Distro)) {
        $tar = "$Root\dl\ubuntu-rootfs.tar.gz"
        Say 'Looking for the Ubuntu base system ...'
        $null = Get-File (Resolve-UbuntuUrls) $tar
        Say 'Creating the private Linux environment (your other WSL systems are not touched) ...'
        & wsl.exe --import $Distro "$Root\distro" $tar --version 2
        if ($LASTEXITCODE -ne 0) {
            Fail 'Import failed. Is virtualization enabled in the BIOS and is WSL 2 available?'
        }
    }
    $img  = "$Root\dl\flipper-os.img.zst"
    $node = "$Root\dl\node.tar.xz"
    $null = Get-File @($ImageUrl) $img
    $haveNode = [bool](@(Get-File $NodeUrls $node $true)[-1])
    if (-not $haveNode) { Warn 'Node.js download failed - using the Ubuntu package source instead.' }
    $sh = "$Root\dl\install.sh"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($sh, ($InstallScript -replace "`r`n", "`n"), $utf8)
    Say 'Setting everything up inside the Linux environment (this takes a few minutes) ...'
    $installArgs = @('-d', $Distro, '-u', 'root', '--exec', '/bin/bash', (ConvertTo-WslPath $sh), (ConvertTo-WslPath $img))
    if ($haveNode) { $installArgs += (ConvertTo-WslPath $node) }
    & wsl.exe @installArgs
    if ($LASTEXITCODE -ne 0) {
        Fail 'Setup inside the Linux environment failed. Please copy the messages above when asking for help.'
    }
    Remove-Item $img -Force -ErrorAction SilentlyContinue
    Set-Content -Path "$Root\installed.flag" -Value (Get-Date).ToString()
    New-DemoShortcuts
    Say 'Installation finished.'
}

function Start-Demo {
    if (-not (Test-Path (Join-Path $MenuDir 'Stop Flipper One.lnk'))) { New-DemoShortcuts }
    if (-not (Test-Server)) {
        Say 'Starting the server in the background ...'
        $guardJs = "process.on('uncaughtException', function (e) { console.error('[guard] uncaughtException: ' + (e && e.stack ? e.stack : e)); });`nprocess.on('unhandledRejection', function (e) { console.error('[guard] unhandledRejection: ' + (e && e.stack ? e.stack : e)); });`n"
        $guardFile = "$Root\guard.js"
        [IO.File]::WriteAllText($guardFile, $guardJs, (New-Object System.Text.UTF8Encoding($false)))
        $q = [string][char]39
        $wslArgs = '-d ' + $Distro + ' -u root --cd /flipperone-testing/fake-flipctl2 --exec /bin/sh -c "while true; do /opt/node/bin/node --require ' + $q + (ConvertTo-WslPath $guardFile) + $q + ' server.js >> /var/log/flipctl.log 2>&1; sleep 3; done"'
        $p = Start-Process wsl.exe -ArgumentList $wslArgs -WindowStyle Hidden -PassThru
        Set-Content -Path "$Root\server.pid" -Value $p.Id
        $ok = $false
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 90) {
            if (Test-Server) { $ok = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $ok) { Warn ('The server is not responding (' + $script:LastErr + '). Continuing anyway.') }
    }
    $b = Find-Browser
    if (-not $b) {
        Warn 'Neither Edge nor Chrome was found - the screen cannot be rendered without one.'
    } elseif (-not (Get-DeviceProcs)) {
        Say 'Starting the invisible device browser ...'
        $devProfile = "$Root\device-profile"
        $bargs = '--headless=new --disable-gpu --no-first-run --no-default-browser-check ' +
                 '--log-level=3 --disable-extensions --disable-sync --disable-component-update --disable-background-networking ' +
                 '--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows ' +
                 '--user-data-dir="' + $devProfile + '" --user-agent="' + $DeviceUA + '" ' + $Url
        Start-Process $b -ArgumentList $bargs -WindowStyle Hidden -RedirectStandardOutput "$Root\device.out.log" -RedirectStandardError "$Root\device.err.log" | Out-Null
        Start-Sleep -Seconds 3
    }
    Start-Process $Url
    Write-Host ''
    Write-Host "Flipper One is running at $Url" -ForegroundColor Green
    Write-Host 'It keeps running in the background, even if you close this window.'
    Write-Host 'To stop it later: Start menu > "Flipper One Demo" > "Stop Flipper One",'
    Write-Host 'or run this file again and choose 3 (Stop).'
    Write-Host ''
    $c = Read-Host 'Type S and press Enter to stop it now, or just press Enter to close this window'
    if ($c -match '^\s*[sS]') { Stop-Demo; Start-Sleep -Seconds 2 }
}

function Stop-Demo {
    Say 'Stopping everything ...'
    Get-DeviceProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$Root\server.pid") {
        $sp = Get-Content "$Root\server.pid" -ErrorAction SilentlyContinue
        if ($sp) { Stop-Process -Id ([int]$sp) -Force -ErrorAction SilentlyContinue }
        Remove-Item "$Root\server.pid" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $QemuPidFile) {
        $qp = Get-Content $QemuPidFile -ErrorAction SilentlyContinue
        if ($qp) { Stop-Process -Id ([int]$qp) -Force -ErrorAction SilentlyContinue }
        Remove-Item $QemuPidFile -Force -ErrorAction SilentlyContinue
    }
    Get-Process -Name 'qemu-system-aarch64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    & wsl.exe -t $Distro *> $null
    Say 'Stopped.'
}

function Uninstall-All {
    Stop-Demo
    & wsl.exe --unregister $Distro *> $null
    if (Test-Path $MenuDir) { Remove-Item -Recurse -Force $MenuDir -ErrorAction SilentlyContinue }
    if (Test-Path $Root) { Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue }
    Say 'Everything has been removed.'
}

function Show-Log {
    Write-Host ''
    Write-Host '--- Last lines of the server log ---' -ForegroundColor Yellow
    & wsl.exe -d $Distro -u root --exec /usr/bin/tail -n 80 /var/log/flipctl.log
    Write-Host '--- End ---' -ForegroundColor Yellow
    Pause-Close
}

# ---------- NEW: Real Flipper OS via QEMU ----------
function Test-Qemu {
    $cmd = Get-Command 'qemu-system-aarch64.exe' -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command 'qemu-system-aarch64' -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\qemu\qemu-system-aarch64.exe",
        "${env:ProgramFiles(x86)}\qemu\qemu-system-aarch64.exe",
        "$env:LOCALAPPDATA\Programs\qemu\qemu-system-aarch64.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $dirs = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}") | Where-Object { $_ -and (Test-Path $_) }
    foreach ($d in $dirs) {
        $f = Get-ChildItem -Path $d -Filter 'qemu-system-aarch64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

function Install-Qemu {
    Say 'QEMU was not found. Trying to install automatically ...'
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            & winget.exe install --id QEMU.QEMU --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) { Say 'QEMU installed via winget.'; return $true }
        } catch { }
    }
    Warn 'winget failed or not available. Trying direct download ...'
    $qemuInstaller = "$Root\dl\qemu-w64-setup.exe"
    $qemuUrls = @(
        'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.exe',
        'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260805.exe',
        'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260729.exe'
    )
    $downloaded = $false
    foreach ($u in $qemuUrls) {
        Say "Downloading: $u"
        & curl.exe -L --fail --retry 2 -o "$qemuInstaller.part" $u
        if ($LASTEXITCODE -eq 0 -and (Test-Path "$qemuInstaller.part")) {
            Move-Item "$qemuInstaller.part" $qemuInstaller -Force
            $downloaded = $true
            break
        }
        Remove-Item "$qemuInstaller.part" -Force -ErrorAction SilentlyContinue
    }
    if ($downloaded) {
        Say 'Running QEMU installer (silent) ...'
        try {
            $p = Start-Process -FilePath $qemuInstaller -ArgumentList '/S' -Wait -PassThru
            if (Test-Qemu) { Say 'QEMU installed.'; return $true }
        } catch { }
        try {
            Start-Process -FilePath $qemuInstaller -Wait
            if (Test-Qemu) { Say 'QEMU installed.'; return $true }
        } catch { }
    }
    Warn 'Automatic QEMU install failed.'
    Write-Host 'Please install QEMU manually: https://www.qemu.org/download/#windows' -ForegroundColor Yellow
    Write-Host 'Then re-run this script and choose option 2.' -ForegroundColor Yellow
    return $false
}

function Find-Firmware {
    $qemu = Test-Qemu
    if (-not $qemu) { return $null }
    $qdir = Split-Path -Parent $qemu
    $searchRoots = @($qdir, (Join-Path $qdir '..\share'), (Join-Path $qdir '..\share\qemu'))
    foreach ($r in $searchRoots) {
        if (-not (Test-Path $r)) { continue }
        $f = Get-ChildItem -Path $r -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'aarch64.*\.fd$|edk2.*aarch64|QEMU_EFI.*\.fd$' } |
            Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    foreach ($name in @('edk2-aarch64-code.fd','QEMU_EFI.fd','AAVMF_CODE.fd')) {
        foreach ($r in $searchRoots) {
            $p = Join-Path $r $name
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Test-RealHttp {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { return $true }
    } catch { }
    return $false
}

function Extract-RealBoot {
    $raw = "$RealRoot\flipper-os.img"
    $bootDir = "$RealRoot\boot"
    New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
    $vmlinuz = Join-Path $bootDir 'vmlinuz'
    $initrd = Join-Path $bootDir 'initrd'
    if ((Test-Path $vmlinuz) -and (Test-Path $initrd)) { return $true }
    if (-not (Test-Distro)) { Warn 'WSL-Distro FlipperOne fehlt.'; return $false }

    $sh = "$RealRoot\extract-boot.sh"
    $bash = @'
#!/bin/bash
set -e
IMG="$1"
OUT="$2"
MNT=/mnt/fliprealboot
LOOP=$(losetup -fP --show "$IMG")
sleep 1
mkdir -p "$MNT"
mount -o ro "$LOOP"p3 "$MNT"
VER=7.3.0-rc7-gd66a9f4f3efa
cp "$MNT/@Minimal/usr/lib/modules/$VER/vmlinuz" "$OUT/vmlinuz"
cp "$MNT/@Minimal/usr/lib/modules/$VER/initrd" "$OUT/initrd"
umount "$MNT"
losetup -d "$LOOP" 2>/dev/null
'@
    [IO.File]::WriteAllText($sh, ($bash -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say 'Kernel und Initramfs werden aus dem Flipper-OS-Image extrahiert ...'
    & wsl.exe -d $Distro -u root --exec /bin/bash (ConvertTo-WslPath $sh) (ConvertTo-WslPath $raw) (ConvertTo-WslPath $bootDir)
    if (-not (Test-Path $vmlinuz) -or -not (Test-Path $initrd)) {
        Warn 'Kernel/Initramfs konnten nicht extrahiert werden.'
        return $false
    }
    return $true
}

function Start-RealOS {
    Say '=== Echtes Flipper OS (experimentell) ==='
    Write-Host ''
    Write-Host 'Hinweis: Flipper OS ist fuer Rockchip RK3576 (ARM) gebaut.' -ForegroundColor Yellow
    Write-Host 'Auf einem x86-Windows-PC laeuft es nur per Emulation (QEMU aarch64).' -ForegroundColor Yellow
    Write-Host 'Echte Hardware (Wi-Fi, Modem, Battery, GPIO) funktioniert nicht.' -ForegroundColor Yellow
    Write-Host 'Wir booten den echten Kernel mit passendem Initramfs direkt in QEMU.' -ForegroundColor Yellow
    Write-Host 'Der erste Start dauert per Emulation 2-5 Minuten.' -ForegroundColor Yellow
    Write-Host ''

    New-Item -ItemType Directory -Force -Path "$Root\dl", $RealRoot | Out-Null
    $img = "$Root\dl\flipper-os.img.zst"
    $raw = "$RealRoot\flipper-os.img"
    if (-not (Test-Path $raw)) {
        if (-not (Test-Path $img)) {
            $null = Get-File @($ImageUrl) $img
        }
        Say 'Entpacke Image (kann einige Minuten dauern) ...'
        $zstd = Get-Command 'zstd.exe' -ErrorAction SilentlyContinue
        if (-not $zstd) {
            if (Test-Distro) {
                $wslImg = ConvertTo-WslPath $img
                $wslRaw = ConvertTo-WslPath $raw
                & wsl.exe -d $Distro -u root --exec /bin/bash -c "zstd -d -f --long=31 '$wslImg' -o '$wslRaw'"
            } else {
                Warn 'zstd nicht gefunden und WSL-Distro nicht verfuegbar.'
                Write-Host 'Installiere zstd oder nutze WSL, dann erneut versuchen.' -ForegroundColor Yellow
                return
            }
        } else {
            & $zstd.Source -d -f --long=31 "$img" -o "$raw"
        }
        if (-not (Test-Path $raw)) { Fail 'Image konnte nicht entpackt werden.' }
    }

    if (-not (Extract-RealBoot)) {
        Write-Host 'Ohne Kernel/Initramfs kann das echte OS nicht booten.' -ForegroundColor Yellow
        Pause-Close
        return
    }

    $qemu = Test-Qemu
    if (-not $qemu) {
        $ok = Install-Qemu
        if ($ok) { $qemu = Test-Qemu }
    }
    if (-not $qemu) { Fail 'QEMU (qemu-system-aarch64) ist nicht verfuegbar.' }
    Say "QEMU: $qemu"

    Stop-Demo | Out-Null
    Start-Sleep -Seconds 2

    $bootDir = "$RealRoot\boot"
    $vmlinuz = Join-Path $bootDir 'vmlinuz'
    $initrd = Join-Path $bootDir 'initrd'
    $serialLog = Join-Path $RealRoot 'serial.log'
    $qemuErr = Join-Path $RealRoot 'qemu.err.log'
    Remove-Item $serialLog, $qemuErr -Force -ErrorAction SilentlyContinue

    # The btrfs filesystem UUID and profile from the official boot entries.
    $rootUuid = '5cf1bcd6-084c-47d5-aae3-3a82b879366c'
    $profile = '@Minimal'
    $append = "root=UUID=$rootUuid rootflags=subvol=$profile rw rootwait ip=dhcp console=ttyS0,115200 console=tty0"
    $appendQuoted = '"' + $append + '"'

    $argsLine = "-M virt -accel tcg -cpu cortex-a72 -m 4096 -smp 4 " +
                "-kernel `"$vmlinuz`" -initrd `"$initrd`" -append $appendQuoted " +
                "-drive `"if=none,file=$raw,format=raw,id=hd0`" -device virtio-blk-device,drive=hd0 " +
                "-netdev user,id=net0,hostfwd=tcp::${Port}-:8899 -device virtio-net-device,netdev=net0 " +
                "-display none -no-reboot " +
                "-chardev file,id=ser0,path=$serialLog -device pci-serial,chardev=ser0"

    Say 'Starte QEMU mit dem echten Flipper-OS-Kernel ...'
    $proc = Start-Process -FilePath $qemu -ArgumentList $argsLine -WindowStyle Hidden -PassThru -RedirectStandardError $qemuErr
    Set-Content -Path $QemuPidFile -Value $proc.Id

    $ok = $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lastReport = -10
    while ($sw.Elapsed.TotalSeconds -lt 300) {
        if (Test-RealHttp) { $ok = $true; break }
        if ($proc.HasExited) { break }
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        if ($elapsed - $lastReport -ge 15) {
            Say "Warte auf Flipper OS ... ${elapsed}s (Emulation ist langsam)"
            $lastReport = $elapsed
        }
        Start-Sleep -Seconds 2
    }

    if (-not $ok) {
        Warn 'Flipper OS hat nicht rechtzeitig auf Port 8899 geantwortet.'
        Write-Host "QEMU-Stderr: $qemuErr" -ForegroundColor Yellow
        Write-Host "Serial-Log:  $serialLog" -ForegroundColor Yellow
        if (Test-Path $serialLog) {
            Write-Host '--- letzte Serial-Ausgaben ---' -ForegroundColor Yellow
            Get-Content $serialLog -Tail 30 -ErrorAction SilentlyContinue
        }
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item $QemuPidFile -Force -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host 'Das Image ist fuer RK3576 gebaut. Wenn der Kernel hier nicht bootet,' -ForegroundColor Yellow
        Write-Host 'braucht es dafuer einen RK3576-SBC (z.B. Armsom Sige5).' -ForegroundColor Yellow
        Pause-Close
        return
    }

    Start-Process $Url
    Write-Host ''
    Write-Host "Echtes Flipper OS laeuft (experimentell) unter $Url" -ForegroundColor Green
    Write-Host 'Der Start dauert per Emulation ein paar Minuten - bitte Geduld.' -ForegroundColor Green
    Write-Host 'Stoppen: dieses Fenster erneut oeffnen -> Option 3 (Stop).' -ForegroundColor Green
    Write-Host ''
    $c = Read-Host 'Type S and press Enter to stop now, or Enter to close this window'
    if ($c -match '^\s*[sS]') { Stop-Demo; Start-Sleep -Seconds 2 }
}

function Show-Menu {
    Write-Host ''
    Write-Host '  [1] FlipCTL (UI-Vorschau) (Standard) - wie bisher'
    Write-Host '  [2] Echtes Flipper OS (experimentell, QEMU aarch64)'
    Write-Host '  [3] Stop'
    Write-Host '  [4] Uninstall (entfernt alles wieder)'
    Write-Host '  [5] Reinstall'
    Write-Host '  [6] Server-Log anzeigen'
    $c = Read-Host '  Auswahl (Enter = 1)'
    switch ($c) {
        '2' { Start-RealOS }
        '3' { Stop-Demo; Start-Sleep -Seconds 2 }
        '4' { Uninstall-All; Start-Sleep -Seconds 3 }
        '5' { Uninstall-All; Install-All; Start-Demo }
        '6' { Show-Log }
        default { Start-Demo }
    }
}

$cmd = ''
if ($env:FLIP_ARGS) { $cmd = $env:FLIP_ARGS.Trim().ToLower() }

Write-Host ''
Write-Host "=== Flipper One Demo v$Version ===" -ForegroundColor Yellow
Write-Host 'Option 1: FlipCTL UI-Vorschau (fake, laeuft stabil auf Windows).'
Write-Host 'Option 2: Echtes Flipper OS per QEMU (experimentell).'

if ($cmd -eq 'stop') { Stop-Demo; Start-Sleep -Seconds 2; exit 0 }
if ($cmd -eq 'real' -or $cmd -eq 'realos') { 
    if (-not ((Test-Path "$Root\installed.flag") -and (Test-WslReady) -and (Test-Distro))) { Install-All }
    Start-RealOS; exit 0 
}
if ($cmd -eq 'start') { Start-Demo; exit 0 }
if ($cmd -eq 'log') { Show-Log; exit 0 }

$installed = (Test-Path "$Root\installed.flag") -and (Test-WslReady) -and (Test-Distro)
if ($installed) {
    Show-Menu
} else {
    Write-Host 'First run: everything is downloaded and set up once (several GB, a few minutes).'
    Install-All
    Start-Demo
}
