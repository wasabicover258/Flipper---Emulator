@echo off
setlocal
title Flipper One Demo v4.0
rem Flipper One Demo - unofficial community helper, v4.0 test build
rem Option 1: FlipCTL preview. Option 2: real Flipper OS in QEMU (aarch64).
set "FLIP_BAT=%~f0"
set "FLIP_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Get-Content -LiteralPath $env:FLIP_BAT -Raw -Encoding UTF8; $i = $f.IndexOf('#PS1' + 'START'); Invoke-Expression $f.Substring($i)"
exit /b %errorlevel%
#PS1START
# =============================================================================
# Flipper One Demo - unofficial community helper (v4.0 test build)
#
# NOT affiliated with or endorsed by Flipper Devices.
#
# Option 1: FlipCTL preview UI (the test UI from the Flipper OS image).
# Option 2: Boots the REAL Flipper OS kernel + initramfs in QEMU (aarch64).
#           The image targets Rockchip RK3576 (ARM); hardware is emulated only.
#           Real Wi-Fi, modem, battery, and GPIO are not available on a PC.
#           The virtual machine gets automatic internet access through
#           QEMU user-mode networking (NAT). Nothing has to be configured.
#
# Everything is installed automatically inside %LOCALAPPDATA%\FlipperOneDemo.
# No administrator rights are required for the app or for QEMU.
# Windows may ask once for permission to enable WSL.
# Option 4 removes everything again.
# =============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$Version       = '4.0'
$Root          = Join-Path $env:LOCALAPPDATA 'FlipperOneDemo'
$DlDir         = Join-Path $Root 'dl'
$DistroDir     = Join-Path $Root 'distro'
$ToolsDir      = Join-Path $Root 'tools'
$RealRoot      = Join-Path $Root 'realos'
$QemuDir       = Join-Path $Root 'qemu'
$QemuExe       = Join-Path $QemuDir 'qemu-system-aarch64.exe'
$BootDir       = Join-Path $RealRoot 'boot'
$Vmlinuz       = Join-Path $BootDir 'vmlinuz'
$Initrd        = Join-Path $BootDir 'initrd'
$RealRaw       = Join-Path $RealRoot 'flipper-os.img'
$GuestNetFlag  = Join-Path $RealRoot 'net-v4.flag'
$QemuPidFile   = Join-Path $Root 'qemu.pid'
$ServerPidFile = Join-Path $Root 'server.pid'
$InstalledFlag = Join-Path $Root 'installed.flag'
$Distro        = 'FlipperOne'
$Port          = 8899
$Url           = "http://127.0.0.1:$Port/"
$ImageUrl      = 'https://dl-linux-images.flipp.dev/full-img/2407/debian-512-sige5-2407.img.zst'
$UbuntuBase    = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/'
$NodeUrls      = @('https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-x64.tar.xz')
$ZstdUrl       = 'https://github.com/meta/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip'
$SevenZipMsiUrl = 'https://www.7-zip.org/a/7z2301-x64.msi'
$SevenZipMsiSha256 = '0BA639B6DACDF573D847C911BD147C6384381A54DAC082B1E8C77BC73D58958B'
$QemuIndex     = 'https://qemu.weilnetz.de/w64/'
$QemuFallbacks = @('qemu-w64-setup-20260811.exe', 'qemu-w64-setup-20260805.exe', 'qemu-w64-setup-20260729.exe')
$DeviceUA      = 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/605.1.15 (KHTML, like Gecko) Cog/0.18.4 WPE'
$MenuDir       = Join-Path ([Environment]::GetFolderPath('Programs')) 'Flipper One Demo'
$script:SelfSource = $env:FLIP_BAT
$script:SelfBackup = $null
$script:LastErr = ''

$InstallScript = @'
#!/bin/bash
# Runs as root inside the private WSL distribution "FlipperOne".
set -Eeuo pipefail
RAW="${1:?Path to the raw image is missing}"
BOOTOUT="${2:?Boot output path is missing}"
NODE_TAR="${3:-}"
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
}
trap cleanup EXIT

log "Installing required packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y btrfs-progs util-linux kpartx rsync xz-utils fdisk e2fsprogs squashfs-tools ca-certificates curl zstd

if [ -n "$NODE_TAR" ] && [ -f "$NODE_TAR" ]; then
  log "Setting up Node.js"
  mkdir -p /opt/node
  tar -xJf "$NODE_TAR" -C /opt/node --strip-components=1
else
  log "Installing Node.js from the Ubuntu packages"
  apt-get install -y nodejs
  mkdir -p /opt/node/bin
  ln -sf "$(command -v node)" /opt/node/bin/node
fi
/opt/node/bin/node --version

log "Mounting the Flipper OS image (read-only)"
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$RAW")" || die "Loop devices are not available. Run 'wsl --update' in PowerShell and try again."
sleep 1
while IFS= read -r p; do [ -n "$p" ] && PARTS+=("$p"); done < <(ls -1 "${LOOP}"p* 2>/dev/null | sort -V || true)
if [ "${#PARTS[@]}" -eq 0 ]; then
  kpartx -avs "$LOOP" >/dev/null 2>&1 && KPARTX=1 || true
  while IFS= read -r p; do [ -n "$p" ] && PARTS+=("$p"); done < <(ls -1 /dev/mapper/"$(basename "$LOOP")"p* 2>/dev/null | sort -V || true)
fi
[ "${#PARTS[@]}" -gt 0 ] || die "No partitions were found in the image."
log "Partitions: ${PARTS[*]}"

BTRFS=""
n=0
for p in "${PARTS[@]}"; do
  n=$((n+1))
  mkdir -p "$MNT/p$n"
  if mount -o ro,subvolid=5 "$p" "$MNT/p$n" 2>/dev/null; then
    if [ -d "$MNT/p$n/@Minimal" ]; then BTRFS="$MNT/p$n"; break; fi
  else
    rmdir "$MNT/p$n" 2>/dev/null || true
  fi
done
[ -n "$BTRFS" ] || die "The Flipper OS root filesystem was not found in the image."

log "Looking for the FlipCTL preview"
SRC=""
while IFS= read -r d; do
  case "$d" in *stock-snapshots*) continue ;; esac
  if [ -f "$d/server.js" ]; then SRC="$(dirname "$d")"; break; fi
done < <(find "$BTRFS" -maxdepth 8 -type d -name fake-flipctl2 2>/dev/null | sort)
[ -n "$SRC" ] || die "No fake-flipctl2 folder was found in the image."
log "Found: $SRC"
log "Copying the preview UI"
mkdir -p /flipperone-testing
rsync -a --delete "$SRC"/ /flipperone-testing/
ln -sfn /flipperone-testing/fake-flipctl2 /flipperone-testing/active-flipctl
[ -f /flipperone-testing/fake-flipctl2/server.js ] || die "server.js is missing after copying."

log "Extracting the kernel and initramfs"
KDIR="$(ls -1d "$BTRFS"/@Minimal/usr/lib/modules/*/ 2>/dev/null | sort -V | tail -n 1)"
if [ -n "$KDIR" ] && [ -f "$KDIR/vmlinuz" ] && [ -f "$KDIR/initrd" ]; then
  mkdir -p "$BOOTOUT"
  cp -f "$KDIR/vmlinuz" "$BOOTOUT/vmlinuz"
  cp -f "$KDIR/initrd" "$BOOTOUT/initrd"
  log "Kernel: $KDIR"
else
  warn "Kernel/initramfs not found. The real OS mode will need a reinstall."
fi

log "Testing the preview server"
cd /flipperone-testing/fake-flipctl2
( timeout 10 /opt/node/bin/node server.js >/tmp/smoke.log 2>&1 & )
ok=0
for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  if curl -fsS http://127.0.0.1:8899/api/version >/dev/null 2>&1; then ok=1; break; fi
done
pkill -f '/flipperone-testing/fake-flipctl2/server.js' 2>/dev/null || true
pkill -f 'node server.js' 2>/dev/null || true
if [ "$ok" = 1 ]; then log "The preview server responds."; else warn "Quick test: no response. Output:"; tail -n 20 /tmp/smoke.log || true; fi
log "Setup inside the Linux environment finished."
'@

# Installs a persistent DHCP profile for QEMU's virtio NIC into the Flipper OS
# image. systemd-networkd then configures eth0 automatically on every boot,
# independent of the image's built-in defaults. Only the @Minimal subvolume is
# touched, and only the virtio_net driver matches, so real hardware is never
# affected. The script is idempotent and fails safely: if anything goes wrong,
# the image keeps its previous behaviour and the built-in DHCP still works.
$GuestNetScript = @'
#!/bin/bash
set -Eeuo pipefail
IMG="${1:?Path to the raw image is missing}"
MNT=/mnt/flipnet
LOOP=""
cleanup() {
  set +e
  umount "$MNT/p" 2>/dev/null || umount -l "$MNT/p" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT/p" "$MNT" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$IMG")"
for i in $(seq 1 10); do [ -b "${LOOP}p1" ] && break; sleep 1; done
DONE=0
for p in "${LOOP}"p*; do
  [ -b "$p" ] || continue
  mkdir -p "$MNT/p"
  if mount -o rw,subvolid=5 "$p" "$MNT/p" 2>/dev/null; then
    if [ -d "$MNT/p/@Minimal/etc" ]; then
      NETDIR="$MNT/p/@Minimal/etc/systemd/network"
      mkdir -p "$NETDIR"
      cat > "$NETDIR/10-qemu-nat.network" <<'EOF'
# Added by Flipper One Demo for QEMU user-mode networking (NAT).
# The emulated machine has no Rockchip Wi-Fi/Ethernet hardware, so this
# virtio NIC is configured automatically via DHCP. Real hardware is not
# affected because the match only applies to the virtio_net driver.
[Match]
Driver=virtio_net
Type=ether

[Network]
DHCP=ipv4

[DHCPv4]
UseDNS=yes
UseRoutes=yes
EOF
      chown root:root "$NETDIR/10-qemu-nat.network"
      chmod 0644 "$NETDIR/10-qemu-nat.network"
      printf '4.0\n' > "$MNT/p/@Minimal/etc/flipper-qemu-net.version"
      chown root:root "$MNT/p/@Minimal/etc/flipper-qemu-net.version"
      chmod 0644 "$MNT/p/@Minimal/etc/flipper-qemu-net.version"
      sync
      grep -q '^DHCP=ipv4$' "$NETDIR/10-qemu-nat.network"
      grep -q '^Driver=virtio_net$' "$NETDIR/10-qemu-nat.network"
      if umount "$MNT/p"; then
        DONE=1
      else
        echo "XX Could not unmount the image cleanly." >&2
        exit 1
      fi
      break
    fi
    umount "$MNT/p" 2>/dev/null || true
  fi
done
[ "$DONE" = 1 ] || { echo "XX The Flipper OS root filesystem was not found." >&2; exit 1; }
echo "OK qemu network profile installed"
'@

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Pause-Close { Read-Host 'Press Enter to close this window' | Out-Null }
function Fail($m) { Write-Host "XX  $m" -ForegroundColor Red; Pause-Close; exit 1 }

function Get-FreeGB {
    try {
        $name = $env:SystemDrive.TrimEnd(':')
        $free = (Get-PSDrive -Name $name -ErrorAction Stop).Free
        return [math]::Round($free / 1GB, 1)
    } catch {
        try { return [math]::Round((Get-PSDrive -Name 'C' -ErrorAction Stop).Free / 1GB, 1) } catch { return 999 }
    }
}

function Assert-Space($gb, $what) {
    $free = Get-FreeGB
    if ($free -lt [double]$gb) {
        Fail ("Not enough free disk space. {0} needs about {1} GB, but only {2} GB are free on {3}." -f $what, $gb, $free, $env:SystemDrive)
    }
}

function Get-File($urls, $dest, $optional = $false) {
    $dest = [string]$dest
    if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 0)) { return $true }
    $parent = Split-Path -Parent $dest
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    foreach ($u in @($urls)) {
        $part = "$dest.part"
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        Say "Downloading: $u"
        $ok = $false
        if (Get-Command 'curl.exe' -ErrorAction SilentlyContinue) {
            & curl.exe -L --fail --retry 3 --retry-delay 2 --progress-bar -o $part $u
            $ok = ($LASTEXITCODE -eq 0)
        } else {
            try {
                Invoke-WebRequest -Uri $u -OutFile $part -UseBasicParsing
                $ok = $true
            } catch { $ok = $false }
        }
        if ($ok -and (Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part).Length -gt 0)) {
            Move-Item -LiteralPath $part -Destination $dest -Force
            return $true
        }
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        Warn "Download failed: $u"
    }
    if ($optional) { return $false }
    Fail ('Download failed. Please check your internet connection and try again: ' + (@($urls) -join ' , '))
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

function Test-DistroHealthy {
    if (-not (Test-Distro)) { return $false }
    & wsl.exe -d $Distro -u root --exec /bin/true *> $null
    return ($LASTEXITCODE -eq 0)
}

function ConvertTo-WslPath($p) {
    $d = $p.Substring(0, 1).ToLower()
    return '/mnt/' + $d + ($p.Substring(2) -replace '\\', '/')
}

function Test-Server {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/version" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200 -and $r.Content -match '"id"') { return $true }
        $script:LastErr = 'HTTP ' + $r.StatusCode
    } catch { $script:LastErr = $_.Exception.Message }
    return $false
}

function Test-PortFree($p) {
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, [int]$p)
        $listener.Start()
        return $true
    } catch { return $false }
    finally {
        if ($listener) { try { $listener.Stop() } catch { } }
    }
}

function Select-FreePort {
    for ($p = $Port; $p -le 8999; $p++) {
        if (Test-PortFree $p) { return $p }
    }
    Fail 'No free local port was found. Please close other programs and try again.'
}

function Ensure-Wsl {
    if (Test-WslReady) { return $true }
    Warn 'WSL (Windows Subsystem for Linux) is required but is not enabled yet.'
    Write-Host ''
    Write-Host 'Windows will now ask once for administrator permission to enable WSL.' -ForegroundColor Yellow
    Write-Host 'This is a Windows requirement. The app itself does not need admin rights.' -ForegroundColor Yellow
    Write-Host ''
    try {
        $p = Start-Process -FilePath 'wsl.exe' -ArgumentList @('--install', '--no-distribution') -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -ne 0) { Warn "The WSL installation returned code $($p.ExitCode)." }
    } catch {
        Fail 'WSL could not be enabled because the administrator prompt was cancelled. Run this file again and allow the prompt.'
    }
    if (Test-WslReady) { Say 'WSL is ready.'; return $true }
    try {
        $resume = '"' + $env:FLIP_BAT + '" resume'
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FlipperOneDemoResume' -Value $resume -Force
    } catch { }
    Write-Host ''
    Write-Host 'Windows needs one restart to finish enabling WSL.' -ForegroundColor Green
    Write-Host 'After you sign in again, this helper continues automatically.' -ForegroundColor Green
    Write-Host 'If it does not, simply double-click this file again.' -ForegroundColor Green
    Pause-Close
    exit 0
}

function Ensure-Distro {
    if (Test-DistroHealthy) { return $true }
    if (Test-Distro) {
        Say 'Repairing the private Linux environment ...'
        & wsl.exe --terminate $Distro *> $null
        Start-Sleep -Seconds 1
        & wsl.exe --unregister $Distro *> $null
    }
    $tar = Join-Path $DlDir 'ubuntu-rootfs.tar.gz'
    Say 'Downloading the Ubuntu base system (about 350 MB) ...'
    $null = Get-File (Resolve-UbuntuUrls) $tar
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null
    Say 'Creating the private Linux environment (your other WSL distributions are not touched) ...'
    & wsl.exe --import $Distro $DistroDir $tar --version 2 *> $null
    if ($LASTEXITCODE -ne 0) {
        & wsl.exe --set-default-version 2 *> $null
        & wsl.exe --import $Distro $DistroDir $tar --version 2 *> $null
    }
    if ($LASTEXITCODE -ne 0) {
        Fail 'The Linux environment could not be created. Make sure virtualization is enabled in your BIOS/UEFI and try again.'
    }
    Remove-Item $tar -Force -ErrorAction SilentlyContinue
    Say 'The Linux environment is ready.'
    return $true
}

function Get-Zstd {
    $exe = Join-Path $ToolsDir 'zstd\zstd.exe'
    if (Test-Path $exe) { return $exe }
    $zip = Join-Path $DlDir 'zstd-win64.zip'
    $null = Get-File @($ZstdUrl) $zip
    $tmp = Join-Path $ToolsDir 'zstd-tmp'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Say 'Unpacking the zstd tool ...'
    try { Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force } catch { Fail "The zstd tool could not be unpacked: $($_.Exception.Message)" }
    $found = Get-ChildItem -Path $tmp -Recurse -Filter 'zstd.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Fail 'The zstd download did not contain zstd.exe.' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $exe) | Out-Null
    Copy-Item -Path (Join-Path $found.Directory.FullName '*') -Destination (Split-Path -Parent $exe) -Recurse -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    return $exe
}

function Ensure-RawImage {
    if ((Test-Path $RealRaw) -and ((Get-Item $RealRaw).Length -gt 5GB)) { return $true }
    if (Test-Path $RealRaw) { Remove-Item $RealRaw -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $DlDir, $RealRoot | Out-Null
    $zst = Join-Path $DlDir 'flipper-os.img.zst'
    if (-not ((Test-Path $zst) -and ((Get-Item $zst).Length -gt 100MB))) {
        Assert-Space 10 'Downloading and unpacking the Flipper OS image'
        $null = Get-File @($ImageUrl) $zst
    }
    $zstd = Get-Zstd
    Assert-Space 7 'Unpacking the Flipper OS image'
    Say 'Unpacking the Flipper OS image (about 6 GB, this can take a few minutes) ...'
    $part = "$RealRaw.part"
    Remove-Item $part -Force -ErrorAction SilentlyContinue
    & $zstd -d -f --long=31 $zst -o $part
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $part)) {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        Fail 'The Flipper OS image could not be unpacked.'
    }
    Move-Item -LiteralPath $part -Destination $RealRaw -Force
    if ((Get-Item $RealRaw).Length -lt 5GB) {
        Remove-Item $RealRaw -Force -ErrorAction SilentlyContinue
        Fail 'The unpacked Flipper OS image is incomplete. Please try again.'
    }
    Remove-Item $GuestNetFlag -Force -ErrorAction SilentlyContinue
    Remove-Item $zst -Force -ErrorAction SilentlyContinue
    Say 'The Flipper OS image is ready.'
    return $true
}

# ---------------------------------------------------------------------------
# QEMU (portable, no administrator rights)
# ---------------------------------------------------------------------------
function Find-SystemQemu {
    $cmd = Get-Command 'qemu-system-aarch64.exe' -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command 'qemu-system-aarch64' -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        "$env:ProgramFiles\qemu\qemu-system-aarch64.exe",
        "${env:ProgramFiles(x86)}\qemu\qemu-system-aarch64.exe",
        "$env:LOCALAPPDATA\Programs\qemu\qemu-system-aarch64.exe"
    )) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Get-QemuPath {
    if (Test-Path $QemuExe) { return $QemuExe }
    return (Find-SystemQemu)
}

function Resolve-QemuUrls {
    $urls = New-Object System.Collections.ArrayList
    try {
        $html = (Invoke-WebRequest -Uri $QemuIndex -UseBasicParsing -TimeoutSec 20).Content
        $names = [regex]::Matches($html, 'href="(qemu-w64-setup-\d+\.exe)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Descending -Unique | Select-Object -First 3
        foreach ($n in $names) { [void]$urls.Add($QemuIndex + $n) }
    } catch { }
    foreach ($n in $QemuFallbacks) {
        $u = $QemuIndex + $n
        if (-not $urls.Contains($u)) { [void]$urls.Add($u) }
    }
    return , $urls.ToArray()
}

function Test-QemuChecksum($url, $file) {
    try {
        $r = Invoke-WebRequest -Uri ($url + '.sha512') -UseBasicParsing -TimeoutSec 20
        $text = ([string]$r.Content).Trim()
        $expected = ''
        if ($text -match '^\d+(\s+\d+)+$') {
            $chars = @()
            foreach ($n in ($text -split '\s+')) {
                if ($n -match '^\d+$') { $chars += [char][int]$n }
            }
            $expected = (-join $chars).Trim()
        } else {
            $expected = ($text -split '\s+')[0]
        }
        if ($expected -notmatch '^[0-9a-fA-F]{128}$') { return $true }
        $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA512).Hash
        return ($actual -ieq $expected)
    } catch {
        return $true
    }
}

function Get-7z {
    $exe = Join-Path $ToolsDir '7zip\7z.exe'
    if (Test-Path $exe) { return $exe }
    $msi = Join-Path $DlDir '7z-x64.msi'
    $null = Get-File @($SevenZipMsiUrl) $msi
    $hash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    if ($hash -ne $SevenZipMsiSha256) {
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        Fail 'The 7-Zip download failed its security check. Please try again.'
    }
    $admin = Join-Path $ToolsDir '7z-admin'
    Remove-Item $admin -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $admin | Out-Null
    Say 'Preparing the unpacking tool ...'
    $msiArgs = @('/a', ('"' + $msi + '"'), '/qn', ('TARGETDIR="' + $admin + '"'))
    $null = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    $found = Get-ChildItem -Path $admin -Recurse -Filter '7z.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Fail 'The unpacking tool could not be prepared.' }
    $dst = Split-Path -Parent $exe
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -Path (Join-Path $found.Directory.FullName '*') -Destination $dst -Recurse -Force
    Remove-Item $admin -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    return $exe
}

function Install-QemuPortable {
    if (Test-Path $QemuExe) { return $true }
    Assert-Space 4 'QEMU'
    Say 'QEMU is required for the real Flipper OS.'
    Say 'Downloading the portable QEMU emulator (about 200 MB) ...'
    $setup = Join-Path $DlDir 'qemu-w64-setup.exe'
    $got = $false
    foreach ($u in (Resolve-QemuUrls)) {
        if (-not (Get-File @($u) $setup $true)) { continue }
        if (Test-QemuChecksum $u $setup) { $got = $true; break }
        Remove-Item $setup -Force -ErrorAction SilentlyContinue
        Warn 'The QEMU download was damaged (checksum mismatch). Trying another mirror ...'
    }
    if (-not $got) {
        if (Find-SystemQemu) {
            Warn 'The automatic QEMU download failed. The QEMU already installed on this PC will be used.'
            return $true
        }
        Fail 'QEMU could not be downloaded. Please check your internet connection and try option 2 again.'
    }
    $seven = Get-7z
    $tmp = Join-Path $Root 'qemu-tmp'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Say 'Unpacking QEMU (about 1.2 GB, please wait) ...'
    & $seven x $setup ("-o" + $tmp) -y -bso0 -bsp0
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Fail 'QEMU could not be unpacked.'
    }
    $found = Get-ChildItem -Path $tmp -Recurse -Filter 'qemu-system-aarch64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Fail 'The QEMU download did not contain the emulator.'
    }
    Remove-Item (Join-Path $tmp '$PLUGINSDIR') -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $QemuDir) { Remove-Item $QemuDir -Recurse -Force -ErrorAction SilentlyContinue }
    $src = $found.Directory.FullName
    if ([IO.Path]::GetFullPath($src).TrimEnd('\') -eq [IO.Path]::GetFullPath($tmp).TrimEnd('\')) {
        Move-Item -LiteralPath $tmp -Destination $QemuDir -Force
    } else {
        Move-Item -LiteralPath $src -Destination $QemuDir -Force
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $setup -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $QemuExe)) { Fail 'QEMU could not be prepared.' }
    Say 'QEMU is ready.'
    return $true
}

# ---------------------------------------------------------------------------
# Browser / shortcuts
# ---------------------------------------------------------------------------
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
        $self = Join-Path $Root 'Flipper-One-Demo.bat'
        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        if ($script:SelfSource -and (Test-Path -LiteralPath $script:SelfSource)) {
            $same = $false
            try { $same = ([IO.Path]::GetFullPath($script:SelfSource) -eq [IO.Path]::GetFullPath($self)) } catch { $same = $false }
            if (-not $same) { Copy-Item -LiteralPath $script:SelfSource -Destination $self -Force -ErrorAction SilentlyContinue }
        }
        if (-not (Test-Path $self)) { return }
        New-Item -ItemType Directory -Force -Path $MenuDir | Out-Null
        $ws = New-Object -ComObject WScript.Shell
        foreach ($item in @(
            @('Flipper One Demo', ''),
            @('Start FlipCTL Preview', 'start'),
            @('Stop Flipper One', 'stop')
        )) {
            $lnk = $ws.CreateShortcut((Join-Path $MenuDir ($item[0] + '.lnk')))
            $lnk.TargetPath = $self
            $lnk.Arguments = $item[1]
            $lnk.WorkingDirectory = $Root
            $lnk.Save()
        }
        $old = Join-Path $MenuDir 'Start Flipper One.lnk'
        if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
    } catch { Warn 'Could not create the Start menu shortcuts.' }
}

function Install-All {
    New-Item -ItemType Directory -Force -Path $DlDir, $DistroDir, $ToolsDir, $RealRoot, $BootDir | Out-Null
    $need = 12
    if ((Test-Path $RealRaw) -and ((Get-Item $RealRaw).Length -gt 5GB)) { $need = 5 }
    Assert-Space $need 'The installation'
    $null = Ensure-Wsl
    $null = Ensure-Distro
    $null = Ensure-RawImage
    $node = Join-Path $DlDir 'node.tar.xz'
    $haveNode = Get-File $NodeUrls $node $true
    if (-not $haveNode) { Warn 'The Node.js download failed. The Ubuntu package will be used instead.' }
    $sh = Join-Path $DlDir 'install.sh'
    [IO.File]::WriteAllText($sh, ($InstallScript -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say 'Preparing the preview UI inside the Linux environment (this takes a few minutes) ...'
    $installArgs = @('-d', $Distro, '-u', 'root', '--exec', '/bin/bash', (ConvertTo-WslPath $sh), (ConvertTo-WslPath $RealRaw), (ConvertTo-WslPath $BootDir))
    if ($haveNode) { $installArgs += (ConvertTo-WslPath $node) }
    & wsl.exe @installArgs
    if ($LASTEXITCODE -ne 0) {
        Fail 'The setup inside the Linux environment failed. Please copy the messages above when asking for help.'
    }
    Set-Content -Path $InstalledFlag -Value ("installed=" + (Get-Date).ToString('u') + "`r`nversion=$Version") -Encoding ASCII
    New-DemoShortcuts
    Remove-Item $node -Force -ErrorAction SilentlyContinue
    Say 'Installation finished.'
}

# ---------------------------------------------------------------------------
# Start / stop / uninstall
# ---------------------------------------------------------------------------
function Stop-RealOS {
    param([switch]$Quiet)
    $stopped = $false
    if (Test-Path $QemuPidFile) {
        $qp = [string](Get-Content $QemuPidFile -ErrorAction SilentlyContinue)
        if ($qp -match '^\d+$') {
            $proc = Get-Process -Id ([int]$qp) -ErrorAction SilentlyContinue
            if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; $stopped = $true }
        }
        Remove-Item $QemuPidFile -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='qemu-system-aarch64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*flipper-os.img*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped = $true
        }
    if ($stopped -and -not $Quiet) { Say 'The real Flipper OS has been stopped.' }
}

function Stop-Demo {
    param([switch]$Quiet)
    if (-not $Quiet) { Say 'Stopping everything ...' }
    Get-DeviceProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path $ServerPidFile) {
        $sp = [string](Get-Content $ServerPidFile -ErrorAction SilentlyContinue)
        if ($sp -match '^\d+$') { Stop-Process -Id ([int]$sp) -Force -ErrorAction SilentlyContinue }
        Remove-Item $ServerPidFile -Force -ErrorAction SilentlyContinue
    }
    Stop-RealOS -Quiet
    & wsl.exe --terminate $Distro *> $null
    if (-not $Quiet) { Say 'Stopped.' }
}

function Get-RunState {
    if (Test-Path $QemuPidFile) {
        $qp = [string](Get-Content $QemuPidFile -ErrorAction SilentlyContinue)
        if ($qp -match '^\d+$' -and (Get-Process -Id ([int]$qp) -ErrorAction SilentlyContinue)) { return 'real Flipper OS running' }
    }
    $q = Get-CimInstance Win32_Process -Filter "Name='qemu-system-aarch64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*flipper-os.img*' } | Select-Object -First 1
    if ($q) { return 'real Flipper OS running' }
    if (Test-Server) { return 'FlipCTL preview running' }
    return 'stopped'
}

function Start-Demo {
    if (-not ((Test-Path $InstalledFlag) -and (Test-DistroHealthy))) { Install-All }
    if (-not (Test-Path $InstalledFlag)) { Fail 'The installation is incomplete. Please choose Reinstall (5).' }
    Stop-RealOS -Quiet
    if (-not (Test-Server)) {
        if (-not (Test-PortFree $Port)) {
            Say 'Port 8899 is busy. Stopping the previous session ...'
            Stop-Demo
            Start-Sleep -Seconds 2
        }
        if (-not (Test-PortFree $Port)) {
            Fail "Port $Port is used by another program. Please close it and try again."
        }
        Say 'Starting the FlipCTL preview server ...'
        $guardJs = "process.on('uncaughtException', function (e) { console.error('[guard] uncaughtException: ' + (e && e.stack ? e.stack : e)); });`nprocess.on('unhandledRejection', function (e) { console.error('[guard] unhandledRejection: ' + (e && e.stack ? e.stack : e)); });`n"
        $guardFile = Join-Path $Root 'guard.js'
        [IO.File]::WriteAllText($guardFile, $guardJs, (New-Object System.Text.UTF8Encoding($false)))
        $q = [string][char]39
        $wslArgs = '-d ' + $Distro + ' -u root --cd /flipperone-testing/fake-flipctl2 --exec /bin/sh -c "while true; do /opt/node/bin/node --require ' + $q + (ConvertTo-WslPath $guardFile) + $q + ' server.js >> /var/log/flipctl.log 2>&1; sleep 3; done"'
        $p = Start-Process wsl.exe -ArgumentList $wslArgs -WindowStyle Hidden -PassThru
        Set-Content -Path $ServerPidFile -Value $p.Id
        $ok = $false
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 90) {
            if (Test-Server) { $ok = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $ok) {
            Warn ('The preview server is not responding (' + $script:LastErr + ').')
            Show-Log
            return
        }
    }
    New-DemoShortcuts
    $b = Find-Browser
    if (-not $b) {
        Warn 'Neither Edge nor Chrome was found. The page will open in your default browser, but the device preview may not render correctly.'
    } elseif (-not (Get-DeviceProcs)) {
        Say 'Starting the invisible device browser ...'
        $devProfile = Join-Path $Root 'device-profile'
        $bargs = '--headless=new --disable-gpu --no-first-run --no-default-browser-check ' +
                 '--log-level=3 --disable-extensions --disable-sync --disable-component-update --disable-background-networking ' +
                 '--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows ' +
                 '--user-data-dir="' + $devProfile + '" --user-agent="' + $DeviceUA + '" ' + $Url
        Start-Process $b -ArgumentList $bargs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Root 'device.out.log') -RedirectStandardError (Join-Path $Root 'device.err.log') | Out-Null
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

function Show-Log {
    Write-Host ''
    if (-not (Test-Distro)) {
        Warn 'The preview has not been installed yet.'
        Pause-Close
        return
    }
    Write-Host '--- Last lines of the preview server log ---' -ForegroundColor Yellow
    & wsl.exe -d $Distro -u root --exec /usr/bin/tail -n 80 /var/log/flipctl.log
    Write-Host '--- End ---' -ForegroundColor Yellow
    Pause-Close
}

function Uninstall-All {
    param([switch]$NoConfirm, [switch]$KeepBackup)
    if (-not $NoConfirm) {
        Write-Host ''
        Write-Host 'This removes ALL of the following:' -ForegroundColor Yellow
        Write-Host '  - the private Linux environment (FlipperOne)'
        Write-Host '  - all downloaded Flipper OS files and the portable emulator'
        Write-Host '  - the Start menu shortcuts and settings'
        Write-Host ''
        $a = Read-Host 'Type YES to remove everything'
        if ($a -ne 'YES') { Say 'Uninstall cancelled.'; return $false }
    }
    Say 'Removing everything ...'
    $runningBat = ''
    $runningFromRoot = $false
    if ($env:FLIP_BAT -and (Test-Path -LiteralPath $env:FLIP_BAT)) {
        $runningBat = [IO.Path]::GetFullPath($env:FLIP_BAT)
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        $runningFromRoot = $runningBat.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
        if ($runningFromRoot) {
            $script:SelfBackup = Join-Path $env:TEMP ('FlipperOneDemo-' + $Version + '.bat')
            Copy-Item -LiteralPath $runningBat -Destination $script:SelfBackup -Force -ErrorAction SilentlyContinue
            $script:SelfSource = $script:SelfBackup
        }
    }
    Stop-Demo
    Stop-RealOS -Quiet
    try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FlipperOneDemoResume' -Force -ErrorAction SilentlyContinue } catch { }
    if (Test-Distro) {
        & wsl.exe --terminate $Distro *> $null
        Start-Sleep -Seconds 1
        & wsl.exe --unregister $Distro *> $null
        if (Test-Distro) {
            Start-Sleep -Seconds 2
            & wsl.exe --unregister $Distro *> $null
        }
    }
    if (Test-Path $MenuDir) { Remove-Item -LiteralPath $MenuDir -Recurse -Force -ErrorAction SilentlyContinue }
    $scheduled = $false
    if (Test-Path $Root) {
        if ($runningFromRoot -and -not $KeepBackup) {
            Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
                Where-Object { [IO.Path]::GetFullPath($_.FullName) -ne $runningBat } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $cleanup = 'ping 127.0.0.1 -n 16 >nul & rmdir /s /q "' + $Root + '"'
            Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $cleanup) -WindowStyle Hidden | Out-Null
            $scheduled = $true
        } elseif ($runningFromRoot) {
            Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
                Where-Object { [IO.Path]::GetFullPath($_.FullName) -ne $runningBat } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            for ($i = 0; $i -lt 10; $i++) {
                Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $Root)) { break }
                Start-Sleep -Seconds 1
            }
        }
    }
    if (-not $KeepBackup -and $script:SelfBackup -and (Test-Path $script:SelfBackup)) {
        Remove-Item $script:SelfBackup -Force -ErrorAction SilentlyContinue
        $script:SelfBackup = $null
    }
    $distroLeft = Test-Distro
    $rootLeft = (Test-Path $Root) -and -not $scheduled
    if ($rootLeft -and $runningFromRoot -and $KeepBackup) {
        $left = Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
            Where-Object { [IO.Path]::GetFullPath($_.FullName) -ne $runningBat }
        $rootLeft = [bool]$left
    }
    if ($rootLeft) {
        Warn "Some files could not be removed: $Root"
        Write-Host 'Please close all browser windows and try option 4 again.' -ForegroundColor Yellow
        return $false
    }
    if ($distroLeft) {
        Warn 'The private Linux environment could not be removed. Please restart Windows and try option 4 again.'
        return $false
    }
    if ($scheduled) {
        Say 'Everything has been removed. The last temporary file is cleaned up when this window closes.'
    } else {
        Say 'Everything has been removed.'
    }
    return $true
}

function Reinstall-All {
    $hadReal = Test-Path (Join-Path $RealRoot 'used.flag')
    Write-Host ''
    Write-Host 'Reinstall removes everything and downloads a fresh copy.' -ForegroundColor Yellow
    Write-Host 'This needs an internet connection and several GB of free space.' -ForegroundColor Yellow
    $a = Read-Host 'Type YES to reinstall'
    if ($a -ne 'YES') { Say 'Reinstall cancelled.'; return }
    if (-not (Uninstall-All -NoConfirm -KeepBackup)) { return }
    Install-All
    if ($script:SelfBackup -and (Test-Path $script:SelfBackup)) {
        Remove-Item $script:SelfBackup -Force -ErrorAction SilentlyContinue
        $script:SelfBackup = $null
        $script:SelfSource = Join-Path $Root 'Flipper-One-Demo.bat'
    }
    if ($hadReal) {
        if (-not (Get-QemuPath)) { $null = Install-QemuPortable }
        Start-RealOS
    } else {
        Start-Demo
    }
}

# ---------------------------------------------------------------------------
# Real Flipper OS via QEMU
# ---------------------------------------------------------------------------
function Extract-RealBoot {
    if ((Test-Path $Vmlinuz) -and (Test-Path $Initrd)) { return $true }
    if (-not (Test-Path $RealRaw)) { return $false }
    if (-not (Test-DistroHealthy)) {
        $null = Ensure-Wsl
        $null = Ensure-Distro
    }
    $sh = Join-Path $RealRoot 'extract-boot.sh'
    $bash = @'
#!/bin/bash
set -Eeuo pipefail
IMG="$1"
OUT="$2"
MNT=/mnt/fliprealboot
LOOP=""
cleanup() {
  set +e
  umount "$MNT/p" 2>/dev/null || umount -l "$MNT/p" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT/p" "$MNT" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$IMG")"
sleep 1
OK=0
for p in "${LOOP}"p*; do
  [ -b "$p" ] || continue
  mkdir -p "$MNT/p"
  if mount -o ro,subvolid=5 "$p" "$MNT/p" 2>/dev/null; then
    if [ -d "$MNT/p/@Minimal" ]; then
      D="$(ls -1d "$MNT/p/@Minimal/usr/lib/modules/"*/ 2>/dev/null | sort -V | tail -n 1)"
      if [ -n "$D" ] && [ -f "$D/vmlinuz" ] && [ -f "$D/initrd" ]; then
        mkdir -p "$OUT"
        cp -f "$D/vmlinuz" "$OUT/vmlinuz"
        cp -f "$D/initrd" "$OUT/initrd"
        OK=1
        break
      fi
    fi
    umount "$MNT/p" 2>/dev/null || true
  fi
done
[ "$OK" = 1 ]
'@
    [IO.File]::WriteAllText($sh, ($bash -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say 'Extracting the kernel and initramfs from the Flipper OS image ...'
    & wsl.exe -d $Distro -u root --exec /bin/bash (ConvertTo-WslPath $sh) (ConvertTo-WslPath $RealRaw) (ConvertTo-WslPath $BootDir)
    return ((Test-Path $Vmlinuz) -and (Test-Path $Initrd))
}

function Set-GuestNetwork {
    param([switch]$Force)
    if (-not $Force -and (Test-Path $GuestNetFlag)) { return $true }
    if (-not (Test-Path $RealRaw)) { return $false }
    if (-not (Test-DistroHealthy)) {
        $null = Ensure-Wsl
        $null = Ensure-Distro
    }
    $sh = Join-Path $RealRoot 'set-network.sh'
    [IO.File]::WriteAllText($sh, ($GuestNetScript -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say 'Configuring automatic internet access for the Flipper OS (one time) ...'
    & wsl.exe -d $Distro -u root --exec /bin/bash (ConvertTo-WslPath $sh) (ConvertTo-WslPath $RealRaw)
    if ($LASTEXITCODE -ne 0) {
        Warn 'The network profile could not be written to the image.'
        Warn 'The Flipper OS will still use its built-in DHCP fallback.'
        return $false
    }
    Set-Content -Path $GuestNetFlag -Value ("patched=" + (Get-Date).ToString('u') + "`r`nversion=$Version") -Encoding ASCII
    Remove-Item $sh -Force -ErrorAction SilentlyContinue
    Say 'Automatic internet access (NAT) is ready.'
    return $true
}

function Test-RealHttp {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 4
        if ($r.StatusCode -ne 200) { return $false }
        $js = Invoke-WebRequest -Uri ($Url + 'remote.js') -UseBasicParsing -TimeoutSec 4
        return ($js.StatusCode -eq 200 -and $js.Content.Length -gt 1000)
    } catch { return $false }
}

function Start-RealOS {
    Say '=== Real Flipper OS (experimental) ==='
    Write-Host ''
    Write-Host 'Flipper OS is built for Rockchip RK3576 (ARM).' -ForegroundColor Yellow
    Write-Host 'On a Windows PC it runs in QEMU (aarch64) software emulation.' -ForegroundColor Yellow
    Write-Host 'Real hardware (Wi-Fi, modem, battery, GPIO) is not available.' -ForegroundColor Yellow
    Write-Host 'The first start usually takes 1-3 minutes.' -ForegroundColor Yellow
    Write-Host ''
    if (-not ((Test-Path $InstalledFlag) -and (Test-DistroHealthy))) { Install-All }
    New-DemoShortcuts
    if (-not (Test-Path $RealRaw)) { $null = Ensure-RawImage }
    if (-not (Extract-RealBoot)) { Fail 'The Flipper OS kernel files are missing. Please choose Reinstall (5).' }
    if (-not (Get-QemuPath)) {
        if (-not (Install-QemuPortable)) { Fail 'QEMU is not available.' }
    }
    $qemu = Get-QemuPath
    if (-not $qemu) { Fail 'QEMU is not available.' }
    Say "QEMU: $qemu"
    Stop-Demo -Quiet
    Start-Sleep -Seconds 2
    $null = Set-GuestNetwork
    $script:Port = Select-FreePort
    $script:Url = "http://127.0.0.1:$Port/"
    Assert-Space 2 'Starting the emulator'
    $serialLog = Join-Path $RealRoot 'serial.log'
    $qemuErr = Join-Path $RealRoot 'qemu.err.log'
    $qemuOut = Join-Path $RealRoot 'qemu.out.log'
    Remove-Item $serialLog, $qemuErr, $qemuOut -Force -ErrorAction SilentlyContinue
    $rootUuid = '5cf1bcd6-084c-47d5-aae3-3a82b879366c'
    $profile = '@Minimal'
    # QEMU has no Flipper panel/buttons, so logind never creates seat1 and the
    # PAM session for flipctl fails. Without that session /run/user/1000 does
    # not exist, and hosted apps cannot get a runtime directory for sway.
    # Point flipctl at /tmp instead, and make SDL use its software renderer:
    # the emulated machine has no GPU, and the OpenGL path makes hosted games
    # (Doom) draw nothing or crash. Both are passed to PID 1, so the flipctl
    # service and everything it starts inherit them.
    $append = "root=UUID=$rootUuid rootflags=subvol=$profile rw rootwait console=ttyS0,115200 console=tty0 " +
              "systemd.setenv=XDG_RUNTIME_DIR=/tmp " +
              "systemd.setenv=SDL_RENDER_DRIVER=software " +
              "systemd.setenv=SDL_VIDEODRIVER=wayland"
    $appendQuoted = '"' + $append + '"'
    $ramGb = 8
    try { $ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 0) } catch { }
    if ($ramGb -ge 8) { $mem = 4096 } elseif ($ramGb -ge 6) { $mem = 3072 } else { $mem = 2048 }
    $smp = [math]::Min(4, [math]::Max(1, [Environment]::ProcessorCount))
    $argsLine = "-M virt -accel tcg -cpu cortex-a72 -m $mem -smp $smp " +
                "-kernel `"$Vmlinuz`" -initrd `"$Initrd`" -append $appendQuoted " +
                "-drive `"if=none,file=$RealRaw,format=raw,id=hd0`" -device virtio-blk-device,drive=hd0 " +
                "-netdev user,id=net0,hostfwd=tcp:127.0.0.1:${Port}-:8899 -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56 " +
                "-display none -no-reboot " +
                "-chardev `"file,id=ser0,path=$serialLog`" -device pci-serial,chardev=ser0"
    Say 'Starting QEMU with the real Flipper OS kernel ...'
    $proc = Start-Process -FilePath $qemu -ArgumentList $argsLine -WindowStyle Hidden -PassThru -RedirectStandardError $qemuErr -RedirectStandardOutput $qemuOut
    Set-Content -Path $QemuPidFile -Value $proc.Id
    $ok = $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lastReport = -10
    while ($sw.Elapsed.TotalSeconds -lt 420) {
        if (Test-RealHttp) { $ok = $true; break }
        if ($proc.HasExited) { break }
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        if ($elapsed - $lastReport -ge 15) {
            Say "Waiting for Flipper OS ... ${elapsed}s (software emulation is slow)"
            $lastReport = $elapsed
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ok) {
        if ($proc.HasExited) {
            Warn "QEMU stopped unexpectedly (exit code $($proc.ExitCode))."
            Remove-Item $QemuPidFile -Force -ErrorAction SilentlyContinue
            Write-Host "QEMU error log: $qemuErr" -ForegroundColor Yellow
            if ((Test-Path $qemuErr) -and ((Get-Item $qemuErr).Length -gt 0)) { Get-Content $qemuErr -Tail 30 }
            if ((Test-Path $serialLog) -and ((Get-Item $serialLog).Length -gt 0)) {
                Write-Host '--- Last serial output ---' -ForegroundColor Yellow
                Get-Content $serialLog -Tail 30
            }
            Write-Host ''
            Write-Host 'The image is built for RK3576. If the kernel does not boot here,' -ForegroundColor Yellow
            Write-Host 'it needs real RK3576 hardware (for example an Armsom Sige5).' -ForegroundColor Yellow
            Pause-Close
            return
        }
        Warn 'The real Flipper OS is still starting after 7 minutes.'
        Write-Host "QEMU is still running. You can wait and open $Url manually." -ForegroundColor Yellow
        Write-Host 'Press S and Enter to stop it, or press Enter to leave it running.' -ForegroundColor Yellow
        $c = Read-Host 'Choice'
        if ($c -match '^\s*[sS]') { Stop-RealOS; Start-Sleep -Seconds 2 }
        return
    }
    Set-Content -Path (Join-Path $RealRoot 'used.flag') -Value ((Get-Date).ToString('u')) -Encoding ASCII
    Start-Process $Url
    Write-Host ''
    Write-Host "The real Flipper OS is running at $Url" -ForegroundColor Green
    Write-Host 'It keeps running in the background, even if you close this window.'
    Write-Host 'To stop it later: Start menu > "Flipper One Demo" > "Stop Flipper One",'
    Write-Host 'or run this file again and choose 3 (Stop).'
    Write-Host ''
    $c = Read-Host 'Type S and press Enter to stop it now, or just press Enter to close this window'
    if ($c -match '^\s*[sS]') { Stop-RealOS; Start-Sleep -Seconds 2 }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  [1] FlipCTL preview  (fast, stable)'
        Write-Host '  [2] Real Flipper OS  (experimental, QEMU emulation)'
        Write-Host '  [3] Stop everything'
        Write-Host '  [4] Uninstall everything'
        Write-Host '  [5] Reinstall'
        Write-Host '  [6] Show server log'
        Write-Host '  [7] Exit'
        Write-Host ('  Status: ' + (Get-RunState)) -ForegroundColor DarkGray
        $c = Read-Host '  Choose an option (Enter = 1)'
        if ($null -eq $c) { return }
        $c = $c.Trim()
        if ($c -eq '') { $c = '1' }
        if ($c -notmatch '^[1-7]$') { Warn 'Please enter a number from 1 to 7.'; continue }
        switch ($c) {
            '1' { Start-Demo; return }
            '2' { Start-RealOS; return }
            '3' { Stop-Demo; Start-Sleep -Seconds 2; return }
            '4' { $null = Uninstall-All; Start-Sleep -Seconds 3; return }
            '5' { Reinstall-All; return }
            '6' { Show-Log; return }
            '7' { return }
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$cmd = ''
if ($env:FLIP_ARGS) { $cmd = $env:FLIP_ARGS.Trim().ToLower() }

Write-Host ''
Write-Host "=== Flipper One Demo v$Version ===" -ForegroundColor Yellow
Write-Host 'Unofficial community helper - not affiliated with Flipper Devices.' -ForegroundColor DarkGray
Write-Host 'Option 1: FlipCTL preview (fast, stable).'
Write-Host 'Option 2: real Flipper OS in QEMU (experimental, slow).'

if ($cmd -eq 'stop') { Stop-Demo; Start-Sleep -Seconds 2; exit 0 }
if ($cmd -eq 'real' -or $cmd -eq 'realos') { Start-RealOS; exit 0 }
if ($cmd -eq 'start') { Start-Demo; exit 0 }
if ($cmd -eq 'log') { Show-Log; exit 0 }
if ($cmd -eq 'uninstall') { $null = Uninstall-All -NoConfirm; exit 0 }
if ($cmd -eq 'qemu') { $null = Install-QemuPortable; Write-Host ('QEMU: ' + (Get-QemuPath)); exit 0 }
if ($cmd -eq 'install') { Install-All; exit 0 }
if ($cmd -eq 'reinstall') {
    $hadReal = Test-Path (Join-Path $RealRoot 'used.flag')
    if (Uninstall-All -NoConfirm -KeepBackup) {
        Install-All
        if ($script:SelfBackup -and (Test-Path $script:SelfBackup)) {
            Remove-Item $script:SelfBackup -Force -ErrorAction SilentlyContinue
            $script:SelfBackup = $null
            $script:SelfSource = Join-Path $Root 'Flipper-One-Demo.bat'
        }
        if ($hadReal) {
            if (-not (Get-QemuPath)) { $null = Install-QemuPortable }
            Start-RealOS
        } else { Start-Demo }
    }
    exit 0
}
if ($cmd -eq 'resume') {
    try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FlipperOneDemoResume' -Force -ErrorAction SilentlyContinue } catch { }
    Install-All
    Show-Menu
    exit 0
}

if (-not ((Test-Path $InstalledFlag) -and (Test-DistroHealthy))) {
    Write-Host ''
    Write-Host 'First start: everything needed is downloaded and set up automatically.' -ForegroundColor Green
    Write-Host 'This can take a few minutes and needs about 9 GB of free disk space.' -ForegroundColor Green
    Write-Host 'Option 1 needs no administrator rights. Option 2 uses portable QEMU.' -ForegroundColor Green
    Write-Host 'Windows may ask once for permission to enable WSL.' -ForegroundColor Green
}
Show-Menu
