@echo off
setlocal
title Flipper Emulator v8.0
rem Flipper Emulator - unofficial community helper, v8.0 development build
rem Option 1: FlipCTL preview. Option 2: real Flipper OS in QEMU (aarch64).
rem Option 3: starts Flipper OS and File Manager, opens both in two browser tabs.
set "FLIP_BAT=%~f0"
set "FLIP_ARGS=%*"
if "%~1"=="" goto :flipgui
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Get-Content -LiteralPath $env:FLIP_BAT -Raw -Encoding UTF8; $i = $f.IndexOf('#PS1' + 'START'); Invoke-Expression $f.Substring($i)"
exit /b %errorlevel%

:flipgui
rem No arguments: open the Windows app in a separate hidden process.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$f = Get-Content -LiteralPath $env:FLIP_BAT -Raw -Encoding UTF8; $i = $f.IndexOf('#PS1' + 'START'); Invoke-Expression $f.Substring($i)"
exit /b 0
#PS1START
# =============================================================================
# Flipper Emulator - unofficial community helper (v8.0 development build)
#
# NOT affiliated with or endorsed by Flipper Devices.
#
# Option 1: FlipCTL preview UI (the test UI from the Flipper OS image).
# Option 2: Boots the REAL Flipper OS kernel + initramfs in QEMU (aarch64).
#           The image targets Rockchip RK3576 (ARM); hardware is emulated only.
#           Real Wi-Fi, modem, battery, and GPIO are not available on a PC.
#           The virtual machine gets automatic internet access through
#           QEMU user-mode networking (NAT). Nothing has to be configured.
# Option 3: Starts the real Flipper OS (if needed) and the File Manager, then
#           opens both in two browser tabs. If the Flipper OS is already running,
#           only the File Manager tab is added; the OS is never restarted.
#           Files live in /home/user/Files and are backed up to
#           %LOCALAPPDATA%\FlipperOneDemoFiles on this PC. Apps appear under
#           Apps in the Flipper OS and can be tested right away.
#
# Everything is installed automatically inside %LOCALAPPDATA%\FlipperOneDemo.
# No administrator rights are required for the app or for QEMU.
# Windows may ask once for permission to enable WSL.
# Option 5 removes the emulator again. The latest files are copied to the PC
# backup first, and a reinstall restores them automatically.
# Option 8 resets the real Flipper OS: the OS image and the PC backup are
# deleted, so the next start begins with a fresh, factory-state Flipper.
# =============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$Version       = '8.0'
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
$ShelfPort     = 8898
$ShelfUrl      = "http://127.0.0.1:$ShelfPort/"
$ShelfPortFile = Join-Path $RealRoot 'shelf.port'
$AppPortFile   = Join-Path $RealRoot 'app.port'
$ShelfFlag     = Join-Path $RealRoot 'shelf-v5.flag'
$FilesMirror   = Join-Path $env:LOCALAPPDATA 'FlipperOneDemoFiles'
$ImageUrl      = 'https://dl-linux-images.flipp.dev/full-img/2407/debian-512-sige5-2407.img.zst'
$UbuntuBase    = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/'
$NodeUrls      = @('https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-x64.tar.xz')
$ZstdUrl       = 'https://github.com/meta/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip'
$SevenZipMsiUrl = 'https://www.7-zip.org/a/7z2301-x64.msi'
$SevenZipMsiSha256 = '0BA639B6DACDF573D847C911BD147C6384381A54DAC082B1E8C77BC73D58958B'
$QemuIndex     = 'https://qemu.weilnetz.de/w64/'
$QemuFallbacks = @('qemu-w64-setup-20260811.exe', 'qemu-w64-setup-20260805.exe', 'qemu-w64-setup-20260729.exe')
$DeviceUA      = 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/605.3.15 (KHTML, like Gecko) Cog/0.18.4 WPE'
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
TMP=""
cleanup() {
  set +e
  [ -n "$TMP" ] && rm -f "$TMP" 2>/dev/null
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
      TMP="$NETDIR/.10-qemu-nat.network.tmp"
      cat > "$TMP" <<'EOF'
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
      chown root:root "$TMP"
      chmod 0644 "$TMP"
      grep -q '^DHCP=ipv4$' "$TMP"
      grep -q '^Driver=virtio_net$' "$TMP"
      mv -f "$TMP" "$NETDIR/10-qemu-nat.network"
      TMP=""
      printf '7.2\n' > "$MNT/p/@Minimal/etc/flipper-qemu-net.version"
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
# File Manager for your own files
#
# The page, the guest service and its systemd unit are embedded below. They are
# written to disk only while the image is being prepared, so this helper stays a
# single self-contained file. The service writes to /home/user/Files, the
# canonical home folder inside Flipper OS.
# ---------------------------------------------------------------------------
$ShelfPython = @'
#!/usr/bin/python3
"""Flipper One Demo 7.2 - Flipper One and Flipper Zero

Serves a small file shelf for /home/user/Files on port 8898 and installs
Flipper app bundles from there into /home/user/Apps.  Only the Python
standard library is used; the guest image already contains Python 3.13.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import sys
import tempfile
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlparse

VERSION = "8.0"
CHUNK = 256 * 1024
MAX_JSON = 64 * 1024
TEMP_PREFIX = ".__shelf-upload-"
TEMP_SUFFIX = ".part"
APPIMAGE_MAGIC = b"AI\x02"
ELF_MAGIC = b"\x7fELF"
ELF_AARCH64 = 183
INSTALL_LOCK = threading.Lock()


def fsync_dir(path: str) -> None:
    """Make a rename/mkdir/delete durable even if QEMU is stopped abruptly."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def is_temp_name(name: str) -> bool:
    return name.startswith(TEMP_PREFIX) and name.endswith(TEMP_SUFFIX)


def is_appimage_name(name: str) -> bool:
    return name.lower().endswith(".appimage")


def check_appimage_header(header: bytes) -> None:
    """Reject files that flipctl cannot run, before copying megabytes."""
    if len(header) < 20 or not header.startswith(ELF_MAGIC):
        raise ShelfError(400, "This is not an executable AppImage.")
    if header[8:11] != APPIMAGE_MAGIC:
        raise ShelfError(400, "This is not a type-2 AppImage, which is the format Flipper OS uses.")
    if int.from_bytes(header[18:20], "little") != ELF_AARCH64:
        raise ShelfError(400, "This AppImage is not built for ARM64 (aarch64), so Flipper OS cannot run it.")


class ShelfError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class Shelf:
    def __init__(self, root: str, apps_root: str):
        self.root = os.path.realpath(root)
        self.apps_root = os.path.realpath(apps_root)
        os.makedirs(self.root, exist_ok=True)
        os.makedirs(self.apps_root, exist_ok=True)
        # Remove half-written uploads left behind by an earlier forced stop.
        for dirpath, _, filenames in os.walk(self.root):
            for name in filenames:
                if is_temp_name(name):
                    try:
                        os.unlink(os.path.join(dirpath, name))
                    except OSError:
                        pass
        # Installs write their temporary file directly into the app folder.
        try:
            with os.scandir(self.apps_root) as it:
                for entry in it:
                    if entry.is_file(follow_symlinks=False) and is_temp_name(entry.name):
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            pass
        except OSError:
            pass

    def resolve(self, rel: str = "") -> str:
        rel = (rel or "").replace("\\", "/").strip("/")
        if "\x00" in rel:
            raise ShelfError(400, "Invalid path.")
        path = os.path.realpath(os.path.join(self.root, rel))
        if path != self.root and not path.startswith(self.root + os.sep):
            raise ShelfError(400, "Path is outside the file shelf.")
        return path

    def relative(self, path: str) -> str:
        path = os.path.normpath(path)
        if path == self.root:
            return ""
        return os.path.relpath(path, self.root).replace(os.sep, "/")

    def app_path(self, name: str) -> str:
        name = clean_name(name)
        if not is_appimage_name(name):
            raise ShelfError(400, "Only .AppImage files can be installed.")
        return os.path.join(self.apps_root, name)

    def installed(self, name: str) -> bool:
        if not is_appimage_name(name):
            return False
        try:
            name = clean_name(name)
        except ShelfError:
            return False
        return os.path.isfile(os.path.join(self.apps_root, name))


def clean_name(name: str) -> str:
    name = (name or "").strip()
    if "/" in name or "\\" in name:
        raise ShelfError(400, "The name cannot contain a slash.")
    if not name or name in (".", ".."):
        raise ShelfError(400, "A file name is required.")
    if any(ord(c) < 32 for c in name):
        raise ShelfError(400, "The file name contains control characters.")
    if len(name.encode("utf-8")) > 255:
        raise ShelfError(400, "The file name is too long.")
    return name


def qget(qs, name: str, default: str = "") -> str:
    values = qs.get(name)
    return values[0] if values else default


class Handler(BaseHTTPRequestHandler):
    server_version = "FlipperFiles/" + VERSION
    protocol_version = "HTTP/1.1"
    shelf: Shelf
    html_path: str

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))

    def _headers(self, status: int, ctype: str, length: int, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        if extra:
            for key, value in extra.items():
                self.send_header(key, value)
        self.end_headers()

    def _json(self, status: int, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._headers(status, "application/json; charset=utf-8", len(data))
        self.wfile.write(data)

    def _fail(self, status: int, message: str):
        self._json(status, {"ok": False, "error": message})

    def _read_json(self):
        length = self.headers.get("Content-Length")
        if length is None:
            raise ShelfError(411, "Content-Length is required.")
        try:
            length = int(length)
        except ValueError:
            raise ShelfError(400, "Invalid Content-Length.")
        if length < 0 or length > MAX_JSON:
            raise ShelfError(413, "Request is too large.")
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ShelfError(400, "Invalid JSON.")
        if not isinstance(data, dict):
            raise ShelfError(400, "Invalid request.")
        return data

    def _html(self):
        try:
            with open(self.html_path, "rb") as fh:
                data = fh.read()
        except OSError:
            data = (b"<!doctype html><meta charset=\"utf-8\"><title>File Manager</title>"
                    b"<h1>File Manager</h1><p>The page file is missing.</p>")
        self._headers(200, "text/html; charset=utf-8", len(data))
        self.wfile.write(data)

    def _status(self):
        usage = shutil.disk_usage(self.shelf.root)
        self._json(200, {
            "ok": True,
            "version": VERSION,
            "root": self.shelf.root,
            "apps_root": self.shelf.apps_root,
            "free": usage.free,
            "total": usage.total,
        })

    def _list(self, qs):
        rel = qget(qs, "path", "")
        folder = self.shelf.resolve(rel)
        if not os.path.isdir(folder):
            raise ShelfError(404, "Folder not found.")
        entries = []
        try:
            with os.scandir(folder) as it:
                for entry in it:
                    if is_temp_name(entry.name):
                        continue
                    try:
                        st = entry.stat(follow_symlinks=False)
                        if entry.is_symlink():
                            kind, size = "link", 0
                        elif entry.is_dir(follow_symlinks=False):
                            kind, size = "dir", 0
                        else:
                            kind, size = "file", st.st_size
                        appimage = kind == "file" and is_appimage_name(entry.name)
                        entries.append({
                            "name": entry.name,
                            "type": kind,
                            "size": size,
                            "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
                            "appimage": appimage,
                            "installed": bool(appimage and self.shelf.installed(entry.name)),
                        })
                    except OSError:
                        continue
        except OSError as exc:
            raise ShelfError(500, "Could not read the folder: %s" % exc)
        entries.sort(key=lambda item: (0 if item["type"] == "dir" else 1, item["name"].casefold()))
        usage = shutil.disk_usage(folder)
        self._json(200, {
            "ok": True,
            "path": self.shelf.relative(folder),
            "entries": entries,
            "free": usage.free,
            "total": usage.total,
        })

    def _download(self, qs):
        rel = qget(qs, "path", "")
        path = self.shelf.resolve(rel)
        if not os.path.isfile(path):
            raise ShelfError(404, "File not found.")
        st = os.stat(path)
        name = os.path.basename(path)
        inline = qget(qs, "inline", "") in ("1", "true", "yes")
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        if not inline:
            ctype = "application/octet-stream"
        disposition = "inline" if inline else "attachment"
        encoded = quote(name, safe="")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(st.st_size))
        self.send_header("Content-Disposition", "%s; filename*=UTF-8''%s" % (disposition, encoded))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        with open(path, "rb") as fh:
            while True:
                chunk = fh.read(CHUNK)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def do_GET(self):
        try:
            url = urlparse(self.path)
            if url.path in ("/", "/index.html"):
                return self._html()
            if url.path == "/favicon.ico":
                return self._headers(204, "image/x-icon", 0)
            if url.path == "/api/status":
                return self._status()
            if url.path == "/api/list":
                return self._list(parse_qs(url.query))
            if url.path == "/api/file":
                return self._download(parse_qs(url.query))
            raise ShelfError(404, "Not found.")
        except ShelfError as exc:
            self._fail(exc.status, exc.message)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # keep the service alive
            self._fail(500, "Unexpected error: %s" % exc)

    def do_PUT(self):
        try:
            url = urlparse(self.path)
            if url.path != "/api/file":
                raise ShelfError(404, "Not found.")
            qs = parse_qs(url.query)
            folder = self.shelf.resolve(qget(qs, "path", ""))
            if not os.path.isdir(folder):
                raise ShelfError(404, "Folder not found.")
            name = clean_name(qget(qs, "name", ""))
            length = self.headers.get("Content-Length")
            if length is None:
                raise ShelfError(411, "Content-Length is required.")
            try:
                length = int(length)
            except ValueError:
                raise ShelfError(400, "Invalid Content-Length.")
            if length < 0:
                raise ShelfError(400, "Invalid Content-Length.")
            if length > shutil.disk_usage(folder).free:
                raise ShelfError(507, "Not enough free space in Flipper OS.")
            dest = os.path.join(folder, name)
            if os.path.isdir(dest):
                raise ShelfError(409, "A folder with this name already exists.")
            fd, tmp = tempfile.mkstemp(prefix=TEMP_PREFIX, suffix=TEMP_SUFFIX, dir=folder)
            try:
                remaining = length
                with os.fdopen(fd, "wb") as out:
                    while remaining > 0:
                        chunk = self.rfile.read(min(CHUNK, remaining))
                        if not chunk:
                            raise ShelfError(400, "The upload was interrupted.")
                        out.write(chunk)
                        remaining -= len(chunk)
                    out.flush()
                    os.fsync(out.fileno())
                os.chmod(tmp, 0o644)
                os.replace(tmp, dest)
                tmp = None
                fsync_dir(folder)
            finally:
                if tmp:
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
            self._json(200, {"ok": True, "name": name, "path": self.shelf.relative(dest)})
        except ShelfError as exc:
            self._fail(exc.status, exc.message)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            self._fail(500, "Upload failed: %s" % exc)

    def do_POST(self):
        try:
            url = urlparse(self.path)
            if url.path not in ("/api/mkdir", "/api/rename", "/api/delete",
                                "/api/install", "/api/uninstall"):
                raise ShelfError(404, "Not found.")
            data = self._read_json()
            if url.path == "/api/mkdir":
                return self._mkdir(data)
            if url.path == "/api/rename":
                return self._rename(data)
            if url.path == "/api/install":
                return self._install(data)
            if url.path == "/api/uninstall":
                return self._uninstall(data)
            return self._delete(data)
        except ShelfError as exc:
            self._fail(exc.status, exc.message)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            self._fail(500, "Request failed: %s" % exc)

    def _mkdir(self, data):
        folder = self.shelf.resolve(str(data.get("path", "")))
        if not os.path.isdir(folder):
            raise ShelfError(404, "Folder not found.")
        name = clean_name(str(data.get("name", "")))
        target = os.path.join(folder, name)
        if os.path.lexists(target):
            raise ShelfError(409, "A file or folder with this name already exists.")
        try:
            os.mkdir(target, 0o755)
        except OSError as exc:
            raise ShelfError(500, "Could not create the folder: %s" % exc)
        fsync_dir(folder)
        self._json(200, {"ok": True, "path": self.shelf.relative(target)})

    def _rename(self, data):
        source = self.shelf.resolve(str(data.get("path", "")))
        if source == self.shelf.root:
            raise ShelfError(400, "The shelf root cannot be renamed.")
        if not os.path.lexists(source):
            raise ShelfError(404, "File or folder not found.")
        name = clean_name(str(data.get("name", "")))
        target = os.path.join(os.path.dirname(source), name)
        if target != source and os.path.lexists(target):
            raise ShelfError(409, "A file or folder with this name already exists.")
        try:
            os.rename(source, target)
        except OSError as exc:
            raise ShelfError(500, "Could not rename: %s" % exc)
        fsync_dir(os.path.dirname(source))
        if os.path.dirname(target) != os.path.dirname(source):
            fsync_dir(os.path.dirname(target))
        self._json(200, {"ok": True, "path": self.shelf.relative(target)})

    def _delete(self, data):
        target = self.shelf.resolve(str(data.get("path", "")))
        if target == self.shelf.root:
            raise ShelfError(400, "The shelf root cannot be deleted.")
        if not os.path.lexists(target):
            raise ShelfError(404, "File or folder not found.")
        try:
            if os.path.islink(target) or not os.path.isdir(target):
                os.unlink(target)
            else:
                shutil.rmtree(target)
        except OSError as exc:
            raise ShelfError(500, "Could not delete: %s" % exc)
        fsync_dir(os.path.dirname(target))
        self._json(200, {"ok": True})

    def _install(self, data):
        source = self.shelf.resolve(str(data.get("path", "")))
        if not os.path.isfile(source):
            raise ShelfError(404, "File not found in the file shelf.")
        name = os.path.basename(source)
        dest = self.shelf.app_path(name)
        overwrite = bool(data.get("overwrite", False))
        try:
            with open(source, "rb") as src:
                check_appimage_header(src.read(20))
                size = os.fstat(src.fileno()).st_size
                with INSTALL_LOCK:
                    if os.path.lexists(dest):
                        if os.path.islink(dest) or not os.path.isfile(dest):
                            raise ShelfError(409, "A folder or special file with this name is in the app folder.")
                        if not overwrite:
                            raise ShelfError(409, "This app is already installed. Choose Reinstall to replace it.")
                    if size > shutil.disk_usage(self.shelf.apps_root).free:
                        raise ShelfError(507, "Not enough free space in Flipper OS.")
                    fd, tmp = tempfile.mkstemp(prefix=TEMP_PREFIX + "app-", suffix=TEMP_SUFFIX,
                                               dir=self.shelf.apps_root)
                    try:
                        with os.fdopen(fd, "wb") as out:
                            src.seek(0)
                            shutil.copyfileobj(src, out, CHUNK)
                            out.flush()
                            os.fsync(out.fileno())
                        os.chmod(tmp, 0o755)
                        os.replace(tmp, dest)
                        tmp = None
                        fsync_dir(self.shelf.apps_root)
                    finally:
                        if tmp:
                            try:
                                os.unlink(tmp)
                            except OSError:
                                pass
        except ShelfError:
            raise
        except OSError as exc:
            raise ShelfError(500, "Could not install the app: %s" % exc)
        self._json(200, {"ok": True, "name": name, "installed": True, "size": size})

    def _uninstall(self, data):
        name = clean_name(str(data.get("name", "")))
        target = self.shelf.app_path(name)
        with INSTALL_LOCK:
            if not os.path.lexists(target):
                raise ShelfError(404, "This app is not installed.")
            if os.path.islink(target) or not os.path.isfile(target):
                raise ShelfError(409, "This app is not a regular file.")
            try:
                os.unlink(target)
            except OSError as exc:
                raise ShelfError(500, "Could not remove the app. Close the app first if it is running. (%s)" % exc)
            fsync_dir(self.shelf.apps_root)
        self._json(200, {"ok": True, "name": name, "installed": False})


def main():
    parser = argparse.ArgumentParser(description="Flipper One Demo File Manager")
    parser.add_argument("--root", default="/home/user/Files")
    parser.add_argument("--apps-root", default="/home/user/Apps")
    parser.add_argument("--port", type=int, default=8898)
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()

    shelf = Shelf(args.root, args.apps_root)
    Handler.shelf = shelf
    Handler.html_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "files-shelf.html")
    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    httpd.daemon_threads = True
    print("File Manager %s on %s:%d, root %s, apps %s" %
          (VERSION, args.bind, args.port, shelf.root, shelf.apps_root), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
'@

$ShelfHtml = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>File Manager · Flipper One</title>
<style>
  :root {
    --ground: #14171C;
    --card: #1D2026;
    --line: #2B2F37;
    --ink: #fff;
    --dim: #8A9099;
    --amber: #FF8200;
    --bad: #FF6B6B;
    --good: #7BC96F;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0; min-height: 100%;
    background: var(--ground);
    color: var(--ink);
    font: 13px/1.5 system-ui, sans-serif;
  }
  button, input { font: inherit; }
  a { color: var(--amber); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .bar {
    position: sticky; top: 0; z-index: 5;
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; padding: 12px 20px;
    background: rgba(20, 23, 28, .96);
    border-bottom: 1px solid var(--line);
    backdrop-filter: blur(6px);
  }
  .brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
  .dot {
    width: 9px; height: 9px; border-radius: 50%;
    background: var(--amber); box-shadow: 0 0 10px var(--amber); flex: none;
  }
  h1 { font-size: 15px; margin: 0; font-weight: 600; letter-spacing: .02em; }
  .ver { color: var(--dim); font-size: 11px; white-space: nowrap; }
  .bar nav { display: flex; align-items: center; gap: 8px; flex: none; }
  main { max-width: 1100px; margin: 0 auto; padding: 22px 20px 40px; }
  .lead {
    display: flex; align-items: flex-end; justify-content: space-between;
    gap: 20px; margin-bottom: 16px;
  }
  .lead h2 { margin: 0 0 2px; font-size: 20px; font-weight: 600; letter-spacing: -.01em; }
  .lead p { margin: 0; color: var(--dim); max-width: 62ch; }
  code {
    color: #d7dbe0; background: #0f1216;
    border: 1px solid var(--line); border-radius: 3px; padding: 0 4px;
  }
  .actions { display: flex; gap: 8px; flex: none; }
  button {
    cursor: pointer; background: transparent; color: var(--amber);
    border: 1px solid var(--amber); border-radius: 4px;
    padding: 5px 11px; font-size: 12px;
    transition: background .12s, color .12s, border-color .12s;
  }
  button:hover:not(:disabled) { background: var(--amber); color: #000; }
  button:disabled { opacity: .45; cursor: default; }
  button.primary { background: var(--amber); color: #000; font-weight: 600; }
  button.primary:hover:not(:disabled) { background: #ffa040; border-color: #ffa040; }
  button.ghost { color: var(--dim); border-color: var(--line); }
  button.ghost:hover:not(:disabled) { color: #000; background: var(--dim); border-color: var(--dim); }
  button.danger { color: var(--dim); border-color: var(--line); }
  button.danger:hover:not(:disabled) { color: #000; background: var(--bad); border-color: var(--bad); }
  button.small { padding: 2px 8px; font-size: 11px; }
  .store {
    display: flex; align-items: flex-start; gap: 12px;
    margin-bottom: 16px; padding: 13px 16px;
    background: linear-gradient(135deg, rgba(255, 130, 0, .12), rgba(255, 130, 0, .03));
    border: 1px solid rgba(255, 130, 0, .35);
    border-radius: 6px;
  }
  .store-mark { color: var(--amber); font-size: 19px; line-height: 1.2; flex: none; }
  .store-copy { min-width: 0; }
  .store strong { display: block; margin-bottom: 2px; }
  .store p { margin: 0; color: var(--dim); max-width: 105ch; }
  .badge {
    display: inline-flex; align-items: center;
    border: 1px solid rgba(123, 201, 111, .5);
    background: rgba(123, 201, 111, .1);
    color: var(--good); border-radius: 99px;
    padding: 0 7px; font-size: 10px; font-weight: 600;
    letter-spacing: .03em; text-transform: uppercase; white-space: nowrap;
  }
  .crumbs {
    display: flex; align-items: center; flex-wrap: wrap; gap: 4px;
    margin: 0 0 10px; color: var(--dim); min-height: 24px;
  }
  .crumbs button { border: 0; padding: 1px 4px; color: var(--dim); font-size: 12px; }
  .crumbs button:hover:not(:disabled) { background: transparent; color: var(--amber); }
  .crumbs .here { color: var(--ink); }
  .crumbs .sep { color: #4a505a; }
  .card { background: var(--card); border-radius: 6px; overflow: hidden; }
  .card-head {
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    padding: 10px 14px; border-bottom: 1px solid var(--line);
    color: var(--dim); font-size: 11px;
  }
  .card-head .stat { color: var(--ink); }
  .card-head .stat.bad { color: var(--bad); }
  .list { min-height: 180px; }
  .row {
    display: grid; grid-template-columns: minmax(0, 1fr) 90px 150px 260px;
    align-items: center; gap: 10px;
    padding: 9px 14px; border-bottom: 1px solid var(--line);
  }
  .row:last-child { border-bottom: 0; }
  .row:hover { background: #22262d; }
  .name { display: flex; align-items: center; gap: 9px; min-width: 0; }
  .icon { width: 18px; text-align: center; flex: none; color: var(--dim); }
  .icon.dir { color: var(--amber); }
  .name button {
    border: 0; padding: 0; color: var(--ink);
    text-align: left; overflow-wrap: anywhere;
  }
  .name button:hover:not(:disabled) { background: transparent; color: var(--amber); }
  .meta { color: var(--dim); font-size: 11px; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .actions-cell { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 6px; row-gap: 4px; }
  .actions-cell button { opacity: .75; white-space: nowrap; }
  .row:hover .actions-cell button { opacity: 1; }
  .empty { padding: 34px 18px; text-align: center; color: var(--dim); }
  .empty strong { display: block; color: var(--ink); margin-bottom: 4px; font-size: 14px; }
  .drop-hint { color: var(--dim); font-size: 12px; }
  .uploads {
    display: grid; gap: 1px; background: var(--line);
    border-radius: 6px; overflow: hidden; margin-top: 14px;
  }
  .uploads:empty { display: none; }
  .upload {
    display: grid; grid-template-columns: minmax(0, 1fr) 130px 60px;
    gap: 12px; align-items: center; padding: 9px 14px; background: var(--card);
  }
  .upload .uname { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar-track { height: 5px; background: #0f1216; border-radius: 99px; overflow: hidden; }
  .bar-fill { height: 100%; width: 0; background: var(--amber); transition: width .15s; }
  .upload .ustat {
    color: var(--dim); font-size: 11px; text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .upload.done .bar-fill { background: var(--good); }
  .upload.fail .bar-fill { background: var(--bad); }
  footer { margin-top: 18px; color: var(--dim); font-size: 11px; line-height: 1.7; }
  .overlay {
    position: fixed; inset: 0; z-index: 20; display: none; place-items: center;
    background: rgba(20, 23, 28, .92);
    border: 3px dashed var(--amber);
    color: var(--amber); font-size: 18px; font-weight: 600;
  }
  .overlay.show { display: grid; }
  .toast {
    position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%);
    max-width: 90vw; background: #2a2f37; color: var(--ink);
    border: 1px solid var(--line); border-left: 3px solid var(--amber);
    border-radius: 4px; padding: 9px 14px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, .45);
    opacity: 0; pointer-events: none; transition: opacity .15s; z-index: 30;
  }
  .toast.show { opacity: 1; }
  .toast.bad { border-left-color: var(--bad); }
  .modal {
    position: fixed; inset: 0; z-index: 25; display: none; place-items: center;
    background: rgba(0, 0, 0, .55); padding: 20px;
  }
  .modal.show { display: grid; }
  .modal-card {
    width: min(420px, 100%); background: var(--card);
    border: 1px solid var(--line); border-radius: 6px;
    box-shadow: 0 18px 50px rgba(0, 0, 0, .55); overflow: hidden;
  }
  .modal-card h3 {
    margin: 0; padding: 14px 16px; font-size: 14px;
    border-bottom: 1px solid var(--line);
  }
  .modal-body { padding: 14px 16px; color: var(--dim); }
  .modal-body p { margin: 0 0 10px; }
  .modal-body input {
    width: 100%; background: var(--ground); color: var(--ink);
    border: 1px solid var(--line); border-radius: 4px; padding: 7px 9px;
  }
  .modal-body input:focus { outline: none; border-color: var(--amber); }
  .modal-actions {
    display: flex; justify-content: flex-end; gap: 8px;
    padding: 12px 16px; border-top: 1px solid var(--line);
  }
  @media (max-width: 760px) {
    .row { grid-template-columns: minmax(0, 1fr) 80px 210px; }
    .row .meta.date { display: none; }
    .lead { align-items: flex-start; flex-direction: column; }
    .bar .ver { display: none; }
  }
  @media (max-width: 520px) {
    main { padding: 16px 12px 30px; }
    .bar { padding: 10px 12px; }
    .row { grid-template-columns: minmax(0, 1fr) auto; }
    .row .meta.size { display: none; }
    .row .actions-cell { grid-column: 1 / -1; justify-content: flex-start; }
    .store { padding: 11px 12px; }
    .store-mark { display: none; }
    .upload { grid-template-columns: minmax(0, 1fr) 90px; }
    .upload .ustat { display: none; }
  }
</style>
</head>
<body>
<header class="bar">
  <div class="brand">
    <span class="dot"></span>
    <h1>File Manager</h1>
    <span class="ver">Flipper One Demo 7.2</span>
  </div>
  <nav>
    <a id="app-link" href="http://127.0.0.1:8899/apps" target="_blank" rel="noopener">App Manager</a>
    <button id="refresh" class="ghost" type="button">Refresh</button>
  </nav>
</header>
<main>
  <div class="lead">
    <div>
      <h2>Your files</h2>
      <p>Stored inside Flipper OS at <code>/home/user/Files</code>. Upload files here or install an app bundle into the OS.</p>
    </div>
    <div class="actions">
      <button id="newdir" class="ghost" type="button">New folder</button>
      <button id="upload" class="primary" type="button">Upload files</button>
    </div>
  </div>
  <section class="store" aria-label="Unofficial app shelf">
    <span class="store-mark" aria-hidden="true">▣</span>
    <div class="store-copy">
      <strong>Unofficial app shelf</strong>
      <p>Put a Flipper app bundle (<code>.AppImage</code>) in this folder, then choose <b>Install</b>. It is copied to <code>/home/user/Apps</code> and appears in Flipper OS under <b>Apps</b>. Only install apps you trust. The bundle must be built for Flipper OS and contain an <code>app.toml</code>; other AppImages are ignored.</p>
    </div>
  </section>
  <div class="crumbs" id="crumbs"></div>
  <section class="card">
    <div class="card-head">
      <span class="stat" id="stat">Loading …</span>
      <span id="space"></span>
    </div>
    <div class="list" id="list"></div>
  </section>
  <div class="uploads" id="uploads"></div>
  <footer>
    Drop files anywhere on this page to upload them. Changes are saved immediately.<br>
    App bundles are installed into <code>/home/user/Apps</code>; only trusted Flipper bundles work. Your files are kept in the PC backup, installed apps are part of the Flipper OS image.<br>
    A backup copy of the Files folder is kept on this PC and restored after a reinstall.
  </footer>
</main>
<div class="overlay" id="overlay">Drop files to upload</div>
<div class="toast" id="toast"></div>
<div class="modal" id="modal">
  <div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="modal-title">
    <h3 id="modal-title"></h3>
    <div class="modal-body">
      <p id="modal-message"></p>
      <input id="modal-input" type="text" autocomplete="off" hidden>
    </div>
    <div class="modal-actions">
      <button id="modal-cancel" class="ghost" type="button">Cancel</button>
      <button id="modal-ok" class="primary" type="button">OK</button>
    </div>
  </div>
</div>
<input id="picker" type="file" multiple hidden>
<script>
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const state = { path: "", busy: false };
  const rootLabel = "Files";

  const appParam = new URLSearchParams(location.search).get("app");
  if (appParam && /^\d{2,5}$/.test(appParam)) {
    const appPort = Number(appParam);
    if (appPort >= 1 && appPort <= 65535) {
      $("app-link").href = "http://127.0.0.1:" + appPort + "/apps";
    }
  }

  const isAppImage = (name) => /\.appimage$/i.test(name || "");

  const fmtSize = (n) => {
    if (!Number.isFinite(n) || n < 0) return "—";
    if (n < 1024) return n + " B";
    const units = ["KB", "MB", "GB", "TB"];
    let value = n / 1024;
    let index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return (value < 10 ? value.toFixed(1) : Math.round(value)) + " " + units[index];
  };

  const fmtDate = (value) => {
    const date = new Date(value);
    if (isNaN(date)) return "";
    const now = new Date();
    const sameYear = date.getFullYear() === now.getFullYear();
    const day = date.toLocaleDateString(undefined,
      sameYear ? { month: "short", day: "numeric" } : { year: "numeric", month: "short", day: "numeric" });
    const time = date.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
    return day + " " + time;
  };

  const join = (a, b) => (a ? a + "/" + b : b);
  const enc = encodeURIComponent;

  function toast(message, bad) {
    const node = $("toast");
    node.textContent = message;
    node.className = "toast show" + (bad ? " bad" : "");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { node.className = "toast"; }, 4200);
  }

  function say(message, bad) {
    const node = $("stat");
    node.textContent = message;
    node.className = "stat" + (bad ? " bad" : "");
  }

  function setBusy(value) {
    state.busy = value;
    for (const button of document.querySelectorAll("button")) button.disabled = value;
    if (!value) renderCrumbs();
  }

  let modalResolve = null;

  function syncModalOk() {
    const input = $("modal-input");
    $("modal-ok").disabled = !input.hidden && !input.value.trim();
  }

  function openModal(options) {
    return new Promise((resolve) => {
      modalResolve = resolve;
      $("modal-title").textContent = options.title || "";
      $("modal-message").textContent = options.message || "";
      const input = $("modal-input");
      input.hidden = !options.withInput;
      input.value = options.value || "";
      const ok = $("modal-ok");
      ok.textContent = options.okLabel || "OK";
      ok.className = options.danger ? "danger" : "primary";
      syncModalOk();
      $("modal").classList.add("show");
      if (options.withInput) {
        setTimeout(() => { input.focus(); input.select(); }, 0);
      } else {
        setTimeout(() => ok.focus(), 0);
      }
    });
  }

  function closeModal(value) {
    $("modal").classList.remove("show");
    const resolve = modalResolve;
    modalResolve = null;
    if (resolve) resolve(value);
  }

  $("modal-cancel").addEventListener("click", () => closeModal(null));
  $("modal-ok").addEventListener("click", () => {
    const input = $("modal-input");
    closeModal(input.hidden ? true : input.value.trim());
  });
  $("modal-input").addEventListener("input", syncModalOk);
  $("modal-input").addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      if (!$("modal-ok").disabled) $("modal-ok").click();
    }
  });
  $("modal").addEventListener("click", (event) => {
    if (event.target === $("modal")) closeModal(null);
  });
  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && $("modal").classList.contains("show")) closeModal(null);
  });

  async function api(url, options) {
    const response = await fetch(url, options);
    let answer = null;
    try { answer = await response.json(); } catch (_) { }
    if (!response.ok || (answer && answer.ok === false)) {
      throw new Error((answer && answer.error) || ("Request failed (HTTP " + response.status + ")"));
    }
    return answer || {};
  }

  function renderCrumbs() {
    const crumbs = $("crumbs");
    crumbs.textContent = "";
    const root = document.createElement("button");
    root.type = "button";
    root.textContent = rootLabel;
    root.className = state.path ? "" : "here";
    root.disabled = state.busy;
    root.addEventListener("click", () => navigate(""));
    crumbs.appendChild(root);

    const parts = state.path ? state.path.split("/") : [];
    let accumulated = "";
    for (const part of parts) {
      accumulated = join(accumulated, part);
      const separator = document.createElement("span");
      separator.className = "sep";
      separator.textContent = "/";
      crumbs.appendChild(separator);
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = part;
      if (accumulated === state.path) button.className = "here";
      button.disabled = state.busy;
      const target = accumulated;
      button.addEventListener("click", () => navigate(target));
      crumbs.appendChild(button);
    }
  }

  function makeButton(label, className, handler) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    button.disabled = state.busy;
    button.addEventListener("click", handler);
    return button;
  }

  function row(entry) {
    const line = document.createElement("div");
    line.className = "row";

    const name = document.createElement("div");
    name.className = "name";
    const icon = document.createElement("span");
    icon.className = "icon" + (entry.type === "dir" ? " dir" : "");
    icon.textContent = entry.type === "dir" ? "▸" : entry.type === "link" ? "↗" : "•";
    const label = document.createElement("button");
    label.type = "button";
    label.textContent = entry.name;
    label.title = entry.name;
    if (entry.type === "dir") {
      label.addEventListener("click", () => navigate(join(state.path, entry.name)));
    } else if (entry.type === "file") {
      label.addEventListener("click", () => download(entry));
    }
    name.append(icon, label);

    const appImage = entry.type === "file" && (entry.appimage === true || isAppImage(entry.name));
    if (appImage && entry.installed) {
      const badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = "Installed";
      badge.title = "Installed in Flipper OS";
      name.append(badge);
    }

    const size = document.createElement("span");
    size.className = "meta size";
    size.textContent = entry.type === "dir" ? "Folder" : entry.type === "link" ? "Link" : fmtSize(entry.size);

    const date = document.createElement("span");
    date.className = "meta date";
    date.textContent = fmtDate(entry.mtime);

    const actions = document.createElement("div");
    actions.className = "actions-cell";
    if (appImage) {
      if (entry.installed) {
        actions.appendChild(makeButton("Reinstall", "small ghost", () => installApp(entry, true)));
        actions.appendChild(makeButton("Remove", "small danger", () => removeApp(entry)));
      } else {
        actions.appendChild(makeButton("Install", "small primary", () => installApp(entry, false)));
      }
    } else if (entry.type === "file") {
      actions.appendChild(makeButton("Download", "small ghost", () => download(entry)));
    }
    actions.appendChild(makeButton("Rename", "small ghost", () => rename(entry)));
    actions.appendChild(makeButton("Delete", "small danger", () => remove(entry)));

    line.append(name, size, date, actions);
    return line;
  }

  function download(entry) {
    const link = document.createElement("a");
    link.href = "/api/file?path=" + enc(join(state.path, entry.name));
    link.download = entry.name;
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function load() {
    setBusy(true);
    say("Loading …");
    try {
      const answer = await api("/api/list?path=" + enc(state.path));
      state.path = answer.path || "";
      const list = $("list");
      list.textContent = "";
      if (!answer.entries || answer.entries.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        const strong = document.createElement("strong");
        strong.textContent = "This folder is empty";
        const hint = document.createElement("span");
        hint.className = "drop-hint";
        hint.textContent = "Drop files here or choose Upload files.";
        empty.append(strong, hint);
        list.appendChild(empty);
      } else {
        for (const entry of answer.entries) list.appendChild(row(entry));
      }
      $("space").textContent = fmtSize(answer.free) + " free";
      say(answer.entries.length + " item" + (answer.entries.length === 1 ? "" : "s"));
      renderCrumbs();
    } catch (error) {
      say("File Manager is not reachable.", true);
      toast(error.message, true);
    } finally {
      setBusy(false);
    }
  }

  function navigate(path) {
    if (state.busy) return;
    state.path = path || "";
    load();
  }

  async function newFolder() {
    if (state.busy) return;
    const name = await openModal({
      title: "New folder",
      message: "Create a folder inside " + (state.path ? "this folder" : "Files") + ".",
      value: "",
      okLabel: "Create",
      withInput: true
    });
    if (name === null || !name) return;
    setBusy(true);
    try {
      await api("/api/mkdir", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: state.path, name })
      });
      toast("Folder created.");
      await load();
    } catch (error) {
      toast(error.message, true);
      setBusy(false);
    }
  }

  async function rename(entry) {
    if (state.busy) return;
    const name = await openModal({
      title: "Rename",
      message: "Enter a new name for “" + entry.name + "”.",
      value: entry.name,
      okLabel: "Rename",
      withInput: true
    });
    if (name === null || name === entry.name) return;
    setBusy(true);
    try {
      await api("/api/rename", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: join(state.path, entry.name), name })
      });
      toast("Renamed.");
      await load();
    } catch (error) {
      toast(error.message, true);
      setBusy(false);
    }
  }

  async function remove(entry) {
    if (state.busy) return;
    const what = entry.type === "dir" ? "folder and everything in it" : "file";
    const ok = await openModal({
      title: "Delete",
      message: "Delete the " + what + " “" + entry.name + "”? This cannot be undone.",
      okLabel: "Delete",
      danger: true,
      withInput: false
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api("/api/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: join(state.path, entry.name) })
      });
      toast("Deleted.");
      await load();
    } catch (error) {
      toast(error.message, true);
      setBusy(false);
    }
  }

  async function installApp(entry, reinstall) {
    if (state.busy) return;
    const ok = await openModal({
      title: reinstall ? "Reinstall app" : "Install app",
      message: (reinstall
        ? "Replace the installed copy of “" + entry.name + "” with this file?"
        : "Install “" + entry.name + "” into Flipper OS? It will appear under Apps.")
        + " Only install apps you trust.",
      okLabel: reinstall ? "Reinstall" : "Install",
      danger: false,
      withInput: false
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api("/api/install", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: join(state.path, entry.name), overwrite: !!reinstall })
      });
      toast(reinstall ? "App replaced. Open Apps to launch it." : "App installed. Open Apps to launch it.");
      await load();
    } catch (error) {
      toast(error.message, true);
      setBusy(false);
    }
  }

  async function removeApp(entry) {
    if (state.busy) return;
    const ok = await openModal({
      title: "Remove app",
      message: "Remove “" + entry.name + "” from Flipper OS? The copy in Files stays. Close the app first if it is running.",
      okLabel: "Remove",
      danger: true,
      withInput: false
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api("/api/uninstall", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: entry.name })
      });
      toast("App removed from Flipper OS.");
      await load();
    } catch (error) {
      toast(error.message, true);
      setBusy(false);
    }
  }

  function uploadRow(name) {
    const line = document.createElement("div");
    line.className = "upload";
    const label = document.createElement("span");
    label.className = "uname";
    label.textContent = name;
    label.title = name;
    const track = document.createElement("div");
    track.className = "bar-track";
    const fill = document.createElement("div");
    fill.className = "bar-fill";
    track.appendChild(fill);
    const status = document.createElement("span");
    status.className = "ustat";
    status.textContent = "0%";
    line.append(label, track, status);
    $("uploads").appendChild(line);
    return { line, fill, status };
  }

  async function uploadFiles(files) {
    const list = Array.from(files || []);
    if (!list.length || state.busy) return;
    setBusy(true);
    const target = state.path;
    say("Uploading " + list.length + " file" + (list.length === 1 ? "" : "s") + " …");
    let good = 0;
    let bad = 0;
    for (const file of list) {
      const ui = uploadRow(file.name);
      try {
        await new Promise((resolve, reject) => {
          const xhr = new XMLHttpRequest();
          xhr.open("PUT", "/api/file?path=" + enc(target) + "&name=" + enc(file.name));
          xhr.upload.addEventListener("progress", (event) => {
            if (!event.lengthComputable) return;
            const percent = Math.max(0, Math.min(100, Math.round(event.loaded / event.total * 100)));
            ui.fill.style.width = percent + "%";
            ui.status.textContent = percent + "%";
          });
          xhr.addEventListener("load", () => {
            if (xhr.status >= 200 && xhr.status < 300) {
              ui.fill.style.width = "100%";
              ui.status.textContent = "Done";
              ui.line.classList.add("done");
              resolve();
              return;
            }
            let message = "HTTP " + xhr.status;
            try {
              const answer = JSON.parse(xhr.responseText);
              if (answer.error) message = answer.error;
            } catch (_) { }
            reject(new Error(message));
          });
          xhr.addEventListener("error", () => reject(new Error("Network error")));
          xhr.addEventListener("abort", () => reject(new Error("Upload cancelled")));
          xhr.send(file);
        });
        good++;
      } catch (error) {
        bad++;
        ui.line.classList.add("fail");
        ui.status.textContent = "Failed";
        ui.line.title = error.message;
      }
    }
    say(bad ? good + " uploaded, " + bad + " failed" : good + " uploaded", bad > 0);
    if (bad) toast(bad + " file(s) could not be uploaded.", true);
    else toast("Upload finished.");
    await load();
    setTimeout(() => { $("uploads").textContent = ""; }, 6000);
  }

  $("refresh").addEventListener("click", load);
  $("newdir").addEventListener("click", newFolder);
  $("upload").addEventListener("click", () => $("picker").click());
  $("picker").addEventListener("change", (event) => {
    uploadFiles(event.target.files);
    event.target.value = "";
  });

  let dragDepth = 0;
  function hasFiles(event) {
    return event.dataTransfer && Array.from(event.dataTransfer.types || []).includes("Files");
  }
  window.addEventListener("dragenter", (event) => {
    if (!hasFiles(event)) return;
    event.preventDefault();
    dragDepth++;
    $("overlay").classList.add("show");
  });
  window.addEventListener("dragover", (event) => {
    if (!hasFiles(event)) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  });
  window.addEventListener("dragleave", (event) => {
    if (!event.dataTransfer) return;
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) $("overlay").classList.remove("show");
  });
  window.addEventListener("drop", (event) => {
    event.preventDefault();
    dragDepth = 0;
    $("overlay").classList.remove("show");
    if (event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files.length) {
      uploadFiles(event.dataTransfer.files);
    }
  });
  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      $("overlay").classList.remove("show");
      dragDepth = 0;
    }
  });

  load();
})();
</script>
</body>
</html>
'@

$ShelfUnit = @'
[Unit]
Description=Flipper One Demo File Manager
Documentation=https://github.com/flipperdevices/flipperone-testing
After=network.target local-fs.target
RequiresMountsFor=/home/user/Files

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/python3 /usr/local/lib/flipper-one-demo/files-shelf.py --root /home/user/Files --apps-root /home/user/Apps --port 8898 --bind 0.0.0.0
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
'@

# Copies the File Manager into the Flipper OS image. The script is idempotent:
# it updates the service files, keeps /home/user/Files untouched, and only
# writes to the @Minimal and @home subvolumes.
$GuestShelfScript = @'
#!/bin/bash
set -Eeuo pipefail
IMG="${1:?Path to the raw image is missing}"
PY="${2:?Path to the service is missing}"
HTML="${3:?Path to the page is missing}"
UNIT="${4:?Path to the unit is missing}"
MNT=/mnt/flipshelf
LOOP=""
cleanup() {
  set +e
  umount "$MNT/p" 2>/dev/null || umount -l "$MNT/p" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT/p" "$MNT" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$IMG")" || { echo "XX Could not attach the image." >&2; exit 1; }
for i in $(seq 1 10); do [ -b "${LOOP}p3" ] && break; sleep 1; done
DONE=0
for p in "${LOOP}"p*; do
  [ -b "$p" ] || continue
  mkdir -p "$MNT/p"
  if mount -o rw,subvolid=5 "$p" "$MNT/p" 2>/dev/null; then
    if [ -d "$MNT/p/@Minimal/etc" ] && [ -d "$MNT/p/@home/user" ]; then
      ROOT="$MNT/p/@Minimal"
      HOME_DIR="$MNT/p/@home/user"
      mkdir -p "$ROOT/usr/local/lib/flipper-one-demo"
      install -m 0755 -o root -g root "$PY" "$ROOT/usr/local/lib/flipper-one-demo/files-shelf.py"
      install -m 0644 -o root -g root "$HTML" "$ROOT/usr/local/lib/flipper-one-demo/files-shelf.html"
      install -m 0644 -o root -g root "$UNIT" "$ROOT/etc/systemd/system/flipper-files-shelf.service"
      mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
      ln -sfn ../flipper-files-shelf.service "$ROOT/etc/systemd/system/multi-user.target.wants/flipper-files-shelf.service"
      install -d -m 0755 -o 1000 -g 1000 "$HOME_DIR/Files"
      install -d -m 0775 -o 1000 -g 1000 "$HOME_DIR/Apps"
      if [ ! -f "$HOME_DIR/Files/README.txt" ]; then
        cat > "$HOME_DIR/Files/README.txt" <<'EOF'
This folder belongs to you.

Files placed here are stored inside Flipper OS at /home/user/Files.
Use the File Manager in the Flipper One Demo menu to upload, download,
rename or delete them while the emulator is running.

You can also keep files in subfolders.
EOF
        chown 1000:1000 "$HOME_DIR/Files/README.txt"
        chmod 0644 "$HOME_DIR/Files/README.txt"
      fi
      printf '7.2\n' > "$ROOT/etc/flipper-files-shelf.version"
      chown root:root "$ROOT/etc/flipper-files-shelf.version"
      chmod 0644 "$ROOT/etc/flipper-files-shelf.version"
      sync
      test -x "$ROOT/usr/local/lib/flipper-one-demo/files-shelf.py"
      test -f "$ROOT/usr/local/lib/flipper-one-demo/files-shelf.html"
      test -f "$ROOT/etc/systemd/system/flipper-files-shelf.service"
      test -L "$ROOT/etc/systemd/system/multi-user.target.wants/flipper-files-shelf.service"
      test -d "$HOME_DIR/Files"
      test -d "$HOME_DIR/Apps"
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
echo "OK File Manager installed in the image"
'@

# Exports or imports /home/user/Files through a temporary loop mount. Used for
# the PC backup and for restoring files after a reinstall.
$GuestFilesScript = @'
#!/bin/bash
set -Eeuo pipefail
IMG="${1:?Path to the raw image is missing}"
MODE="${2:?Mode is missing}"
HOSTDIR="${3:?Path to the PC backup is missing}"
# QEMU is stopped before this runs. Mount read-write so btrfs can replay its
# log after a hard shutdown; export itself only reads from the image.
MOUNT_OPT="rw"
MNT=/mnt/flipfiles
LOOP=""
cleanup() {
  set +e
  umount "$MNT/p" 2>/dev/null || umount -l "$MNT/p" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT/p" "$MNT" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$MNT"
LOOP="$(losetup -fP --show "$IMG")" || { echo "XX Could not attach the image." >&2; exit 1; }
for i in $(seq 1 10); do [ -b "${LOOP}p3" ] && break; sleep 1; done
DONE=0
for p in "${LOOP}"p*; do
  [ -b "$p" ] || continue
  mkdir -p "$MNT/p"
  if mount -o "$MOUNT_OPT",subvolid=5 "$p" "$MNT/p" 2>/dev/null; then
    if [ -d "$MNT/p/@Minimal/etc" ] && [ -d "$MNT/p/@home/user" ]; then
      GUEST="$MNT/p/@home/user/Files"
      if [ "$MODE" = "Export" ]; then
        if [ -d "$GUEST" ]; then
          mkdir -p "$HOSTDIR"
          rsync -rltL --delete --exclude='.__shelf-upload-*.part' "$GUEST"/ "$HOSTDIR"/
          echo "OK files exported to the PC backup"
        else
          echo "OK no files to export yet"
        fi
      else
        if [ -d "$HOSTDIR" ] && [ -n "$(ls -A "$HOSTDIR" 2>/dev/null)" ]; then
          install -d -m 0755 -o 1000 -g 1000 "$GUEST"
          rsync -rltLp --chown=1000:1000 --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --exclude='.__shelf-upload-*.part' "$HOSTDIR"/ "$GUEST"/
          echo "OK files restored from the PC backup"
        else
          echo "OK no PC backup to restore"
        fi
      fi
      sync
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
'@

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Pause-Close {
    # A GUI action runs in a hidden child process. The app window shows the
    # result and keeps the activity log visible, so there is nothing to pause.
    if ($env:FLIP_UI -eq '1') { return }
    Read-Host 'Press Enter to close this window' | Out-Null
}
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
    if ($env:FLIP_UI -eq '1') { Write-Host 'UI-EVENT:RESTART_REQUIRED' }
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
            @('Start Real Flipper OS', 'real'),
            @('Open File Manager', 'files'),
            @('Open PC File Backup', 'backup'),
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

function Update-InstalledFlag {
    if (-not (Test-Path $InstalledFlag)) { return }
    $installed = ''
    foreach ($line in (Get-Content -LiteralPath $InstalledFlag -ErrorAction SilentlyContinue)) {
        if ($line -match '^installed=(.+)$') { $installed = $Matches[1].Trim(); break }
    }
    if (-not $installed) { $installed = (Get-Date).ToString('u') }
    try {
        Set-Content -Path $InstalledFlag -Value ("installed=$installed`r`nversion=$Version") -Encoding ASCII -ErrorAction Stop
    } catch { }
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
    if (-not (Test-Path $InstalledFlag)) { Fail 'The installation is incomplete. Please choose Reinstall (6).' }
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
    Update-InstalledFlag
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
    Write-Host 'It keeps running in the background. Use option 4 in this menu to stop it.'
}

function Show-Log {
    Write-Host ''
    if (-not (Test-Distro)) {
        Warn 'The preview has not been installed yet.'
        return
    }
    Write-Host '--- Last lines of the preview server log ---' -ForegroundColor Yellow
    & wsl.exe -d $Distro -u root --exec /usr/bin/tail -n 80 /var/log/flipctl.log
    Write-Host '--- End ---' -ForegroundColor Yellow
}

function Uninstall-All {
    param([switch]$NoConfirm, [switch]$KeepBackup, [switch]$Wipe)
    $freeBefore = Get-FreeGB
    if (-not $NoConfirm -and $Wipe) {
        Write-Host ''
        Write-Host 'This removes EVERYTHING the helper put on this PC:' -ForegroundColor Yellow
        Write-Host '  - the private Linux environment (FlipperOne) with the Flipper Zero emulator'
        Write-Host '  - the portable QEMU, the Flipper OS image and all downloaded firmwares'
        Write-Host '  - your File Manager files and the PC file backup'
        Write-Host '  - the Start menu shortcuts, settings and temporary files'
        Write-Host ''
        $a = Read-Host 'Type DELETE to remove everything'
        if ($a -cne 'DELETE') { Say 'Cancelled. Nothing was changed.'; return $false }
    } elseif (-not $NoConfirm) {
        Write-Host ''
        Write-Host 'This removes ALL of the following:' -ForegroundColor Yellow
        Write-Host '  - the private Linux environment (FlipperOne)'
        Write-Host '  - all downloaded Flipper OS files and the portable emulator'
        Write-Host '  - the Start menu shortcuts and settings'
        Write-Host ''
        Write-Host 'Your File Manager files are copied to the PC backup first.' -ForegroundColor Green
        $a = Read-Host 'Type YES to remove everything'
        if ($a -ne 'YES') { Say 'Uninstall cancelled.'; return $false }
    }
    if ((-not $Wipe) -and (Test-Path $ShelfFlag) -and (Test-Path $RealRaw)) {
        Write-Host 'Saving the latest File Manager files to this PC first ...' -ForegroundColor Yellow
        Stop-RealOS -Quiet
        Start-Sleep -Seconds 2
        if (-not (Sync-GuestFiles -Mode Export)) {
            Warn 'The latest files could not be copied. The existing PC backup is kept.'
        }
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
    if ($Wipe -and (Test-Distro)) { Stop-ZeroEmulator -Quiet }
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
    $leftoversOk = $true
    if ($Wipe) {
        $lr = @(Remove-FlipperLeftovers)
        $leftoversOk = ($lr.Count -eq 0 -or $lr[-1] -eq $true)
        Remove-Item -LiteralPath $script:ZeroFlag -Force -ErrorAction SilentlyContinue
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
        Write-Host 'Please close all browser windows and try option 5 again.' -ForegroundColor Yellow
        return $false
    }
    if ($distroLeft) {
        Warn 'The private Linux environment could not be removed. Please restart Windows and try option 5 again.'
        return $false
    }
    if (-not $leftoversOk) {
        Warn 'Some temporary files could not be removed. Close other windows of this program and run it again.'
        return $false
    }
    if ($scheduled) {
        Say 'Everything has been removed. The last temporary file is cleaned up when this window closes.'
    } else {
        Say 'Everything has been removed.'
    }
    if ($Wipe) {
        $freeAfter = Get-FreeGB
        Say ("Free disk space on {0} is now {1} GB (before: {2} GB)." -f $env:SystemDrive, $freeAfter, $freeBefore)
        Write-Host 'The Windows feature WSL itself stays installed (it is part of Windows).' -ForegroundColor DarkGray
    }
    return $true
}

function Reset-Flipper {
    param([switch]$NoConfirm)
    Write-Host ''
    Write-Host 'Factory reset of the real Flipper OS' -ForegroundColor Yellow
    Write-Host 'This deletes:'
    Write-Host '  - the real Flipper OS image: all apps, settings and files inside it'
    Write-Host '  - the PC file backup in %LOCALAPPDATA%\FlipperOneDemoFiles'
    Write-Host ''
    Write-Host 'This keeps:'
    Write-Host '  - this Windows helper, its downloads and the FlipCTL preview'
    Write-Host ''
    if (-not $NoConfirm) {
        $a = Read-Host 'Type RESET to erase the Flipper OS and its files'
        if ($a -cne 'RESET') { Say 'Reset cancelled. Nothing was changed.'; return $false }
    } else {
        Write-Host 'Reset confirmed in the Flipper Emulator app.' -ForegroundColor Green
    }
    Stop-Demo
    Start-Sleep -Seconds 2
    $ok = $true
    if (Test-Path $RealRoot) {
        Write-Host 'Deleting the Flipper OS image ...' -ForegroundColor Yellow
        for ($i = 0; $i -lt 15; $i++) {
            Remove-Item -LiteralPath $RealRoot -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $RealRoot)) { break }
            Start-Sleep -Seconds 1
        }
        if (Test-Path $RealRoot) {
            $ok = $false
            Warn "The Flipper OS image could not be removed: $RealRoot"
        }
    }
    if (Test-Path $FilesMirror) {
        Write-Host 'Deleting the PC file backup ...' -ForegroundColor Yellow
        for ($i = 0; $i -lt 15; $i++) {
            Remove-Item -LiteralPath $FilesMirror -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $FilesMirror)) { break }
            Start-Sleep -Seconds 1
        }
        if (Test-Path $FilesMirror) {
            $ok = $false
            Warn "The PC file backup could not be removed: $FilesMirror"
        }
    }
    if ($ok) {
        Write-Host ''
        Say 'The Flipper OS has been reset to factory state.'
        Write-Host 'The next start creates a fresh Flipper. Apps, settings and files inside it are gone.' -ForegroundColor Green
        Write-Host 'The FlipCTL preview and this helper are unchanged.' -ForegroundColor Green
        return $true
    }
    Warn 'The reset did not finish. Close any open File Manager tabs and try option 8 again.'
    return $false
}

function Reinstall-All {
    param([switch]$NoConfirm)
    $hadReal = Test-Path (Join-Path $RealRoot 'used.flag')
    Write-Host ''
    Write-Host 'Reinstall removes everything and downloads a fresh copy.' -ForegroundColor Yellow
    Write-Host 'This needs an internet connection and several GB of free space.' -ForegroundColor Yellow
    if (-not $NoConfirm) {
        $a = Read-Host 'Type YES to reinstall'
        if ($a -ne 'YES') { Say 'Reinstall cancelled.'; return }
    } else {
        Write-Host 'Reinstall confirmed in the Flipper Emulator app.' -ForegroundColor Green
    }
    if (-not (Uninstall-All -NoConfirm -KeepBackup)) { return }
    Install-All
    if ($script:SelfBackup -and (Test-Path $script:SelfBackup)) {
        Remove-Item $script:SelfBackup -Force -ErrorAction SilentlyContinue
        $script:SelfBackup = $null
        $script:SelfSource = Join-Path $Root 'Flipper-One-Demo.bat'
    }
    if ($hadReal) {
        $null = Sync-GuestFiles -Mode Import
        if (-not (Get-QemuPath)) { $null = Install-QemuPortable }
        Start-RealOS
    } else {
        Start-Demo
    }
}

# ---------------------------------------------------------------------------
# File Manager helpers
# ---------------------------------------------------------------------------
function Read-ShelfPort {
    if (Test-Path $ShelfPortFile) {
        $p = [string](Get-Content -LiteralPath $ShelfPortFile -ErrorAction SilentlyContinue)
        if ($p -match '^\d+$') { return [int]$p }
    }
    return $ShelfPort
}

function Read-AppPort {
    if (Test-Path $AppPortFile) {
        $p = [string](Get-Content -LiteralPath $AppPortFile -ErrorAction SilentlyContinue)
        if ($p -match '^\d+$') { return [int]$p }
    }
    return $Port
}

function Test-ShelfHttp {
    param([int]$ShelfPortToTest = 0)
    if ($ShelfPortToTest -le 0) { $ShelfPortToTest = Read-ShelfPort }
    if ($ShelfPortToTest -le 0) { return $false }
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$ShelfPortToTest/api/status" -UseBasicParsing -TimeoutSec 4
        return ($r.StatusCode -eq 200 -and $r.Content -match '"ok"\s*:\s*true')
    } catch { return $false }
}

function Select-FreeShelfPort {
    for ($p = $ShelfPort; $p -le ($ShelfPort + 9); $p++) {
        if ($p -eq $Port) { continue }
        if (Test-PortFree $p) { return $p }
    }
    Fail 'No free local port was found for the File Manager. Please close other programs and try again.'
}

function Write-ShelfSources {
    $dir = Join-Path $RealRoot 'shelf'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $py = Join-Path $dir 'files-shelf.py'
    $html = Join-Path $dir 'files-shelf.html'
    $unit = Join-Path $dir 'files-shelf.service'
    [IO.File]::WriteAllText($py, ($ShelfPython -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($html, ($ShelfHtml -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($unit, ($ShelfUnit -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return @($py, $html, $unit)
}

function Set-GuestShelf {
    param([switch]$Force)
    if (-not $Force -and (Test-Path $ShelfFlag)) {
        $flagText = [string](Get-Content -LiteralPath $ShelfFlag -ErrorAction SilentlyContinue)
        if ($flagText -match ('version=' + [regex]::Escape($Version))) { return 'skipped' }
    }
    if (-not (Test-Path $RealRaw)) { return 'failed' }
    if (-not (Test-DistroHealthy)) {
        $null = Ensure-Wsl
        $null = Ensure-Distro
    }
    $sources = Write-ShelfSources
    $sh = Join-Path $RealRoot 'set-shelf.sh'
    [IO.File]::WriteAllText($sh, ($GuestShelfScript -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say 'Preparing the File Manager inside the Flipper OS (one time, about 10 seconds) ...'
    Say 'Your apps and files are kept.'
    & wsl.exe -d $Distro -u root --exec /bin/bash (ConvertTo-WslPath $sh) (ConvertTo-WslPath $RealRaw) (ConvertTo-WslPath $sources[0]) (ConvertTo-WslPath $sources[1]) (ConvertTo-WslPath $sources[2]) | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Warn 'The File Manager could not be added to the image.'
        Warn 'The Flipper OS itself is unchanged and will still start.'
        return 'failed'
    }
    Set-Content -Path $ShelfFlag -Value ("patched=" + (Get-Date).ToString('u') + "`r`nversion=$Version") -Encoding ASCII
    Remove-Item $sh -Force -ErrorAction SilentlyContinue
    Say 'File Manager is ready.'
    return 'patched'
}

function Sync-GuestFiles {
    param([ValidateSet('Export','Import')][string]$Mode)
    if (-not (Test-Path $RealRaw)) { return $false }
    if (-not (Test-DistroHealthy)) { return $false }
    New-Item -ItemType Directory -Force -Path $FilesMirror | Out-Null
    $sh = Join-Path $RealRoot 'sync-files.sh'
    [IO.File]::WriteAllText($sh, ($GuestFilesScript -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    if ($Mode -eq 'Export') { Say 'Backing up your files from the Flipper OS ...' }
    else { Say 'Restoring your files into the fresh Flipper OS ...' }
    & wsl.exe -d $Distro -u root --exec /bin/bash (ConvertTo-WslPath $sh) (ConvertTo-WslPath $RealRaw) $Mode (ConvertTo-WslPath $FilesMirror)
    $ok = ($LASTEXITCODE -eq 0)
    if (-not $ok) { Warn 'The file backup/restore step did not finish.' }
    Remove-Item $sh -Force -ErrorAction SilentlyContinue
    return $ok
}

function Open-FileShelf {
    if (-not ((Test-Path $InstalledFlag) -and (Test-DistroHealthy))) { Install-All }
    if (-not (Test-Path $InstalledFlag)) { Fail 'The installation is incomplete. Please choose Reinstall (6).' }
    New-DemoShortcuts
    $state = Get-RunState
    if ($state -like 'real Flipper OS running*') {
        $script:Port = Read-AppPort
        $script:Url = "http://127.0.0.1:$Port/"
        $sp = Read-ShelfPort
        $script:ShelfPort = $sp
        $script:ShelfUrl = "http://127.0.0.1:$sp/"
        if (-not (Test-ShelfHttp -ShelfPortToTest $sp)) {
            # QEMU may just have started; give the guest service a moment
            # before offering a restart.
            Say 'Waiting for the File Manager ...'
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Seconds 2
                if (Test-ShelfHttp -ShelfPortToTest $sp) { break }
            }
        }
        if (Test-ShelfHttp -ShelfPortToTest $sp) {
            # The Flipper OS is already running. Reopen its tab in case it was
            # closed, and point at the File Manager without opening a duplicate
            # tab for it (it is already available at the address below).
            Start-Process $Url
            $openUrl = "${ShelfUrl}?app=$Port"
            Write-Host ''
            Write-Host "Flipper OS is already running at $Url" -ForegroundColor Green
            Write-Host "File Manager (already available): $openUrl" -ForegroundColor Green
            Write-Host 'The running Flipper OS was not restarted.'
            return
        }
        Write-Host ''
        Warn 'The File Manager is not active in this running session.'
        Write-Host 'This is normal after updating from an older version: the Flipper OS needs one restart to add it.' -ForegroundColor Yellow
        if ($env:FLIP_UI -eq '1') {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "The File Manager is not active in the running Flipper OS.`n`n" +
                "This is normal after updating from an older version. The Flipper OS needs one restart to add it.`n`n" +
                "Restart the Flipper OS now?",
                'Flipper Emulator - File Manager',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                Stop-Demo -Quiet
                Start-Sleep -Seconds 2
                Start-RealOS -Shelf -NoPrompt -ForceShelf -NoOpen
                Start-Process $Url
                Start-Process "${ShelfUrl}?app=$Port"
            } else {
                Write-Host 'The Flipper OS was not restarted.' -ForegroundColor Yellow
            }
        } else {
            $a = Read-Host 'Restart the Flipper OS now? Type Y'
            if ($a -match '^\s*[yY]') {
                Stop-Demo -Quiet
                Start-Sleep -Seconds 2
                Start-RealOS -Shelf -NoPrompt -ForceShelf -NoOpen
                Start-Process $Url
                Start-Process "${ShelfUrl}?app=$Port"
            } else {
                Write-Host 'Start the Flipper OS again with option 2, then choose option 3.' -ForegroundColor Yellow
            }
        }
        return
    }
    Say 'The real Flipper OS and the File Manager are not running. Starting both ...'
    Start-RealOS -Shelf -NoPrompt -NoOpen
    $script:Port = Read-AppPort
    $script:Url = "http://127.0.0.1:$Port/"
    $script:ShelfPort = Read-ShelfPort
    $script:ShelfUrl = "http://127.0.0.1:$ShelfPort/"
    if (-not (Test-RealHttp)) {
        Warn 'The Flipper OS did not answer. Open the addresses above again in a moment.'
        return
    }
    $openUrl = "${ShelfUrl}?app=$Port"
    Start-Process $Url
    Start-Process $openUrl
    Write-Host ''
    Write-Host "Flipper OS:   $Url" -ForegroundColor Green
    Write-Host "File Manager: $openUrl" -ForegroundColor Green
    Write-Host 'Both are open in two browser tabs.'
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
    Say 'Preparing automatic internet access for the Flipper OS (one time, about 10 seconds) ...'
    Say 'Please keep this window open until this step has finished.'
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
    param([switch]$Shelf, [switch]$NoPrompt, [switch]$ForceShelf, [switch]$NoOpen)
    $state = Get-RunState
    if ($state -like 'real Flipper OS running*') {
        $script:Port = Read-AppPort
        $script:Url = "http://127.0.0.1:$Port/"
        $script:ShelfPort = Read-ShelfPort
        $script:ShelfUrl = "http://127.0.0.1:$ShelfPort/"
        Say 'The real Flipper OS is already running - reusing it.'
        Write-Host "The Flipper OS is running at $Url" -ForegroundColor Green
        if (Test-ShelfHttp) {
            Write-Host "File Manager: ${ShelfUrl}?app=$Port" -ForegroundColor Green
        }
        if (-not $NoOpen) { Start-Process $Url }
        return
    }
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
    if (-not (Extract-RealBoot)) { Fail 'The Flipper OS kernel files are missing. Please choose Reinstall (6).' }
    if (-not (Get-QemuPath)) {
        if (-not (Install-QemuPortable)) { Fail 'QEMU is not available.' }
    }
    $qemu = Get-QemuPath
    if (-not $qemu) { Fail 'QEMU is not available.' }
    Say "QEMU: $qemu"
    Stop-Demo -Quiet
    Start-Sleep -Seconds 2
    # Only back up an image that already has the File Manager. On a fresh
    # install/reinstall this folder is new, and the mirror must win instead.
    if (Test-Path $ShelfFlag) { $null = Sync-GuestFiles -Mode Export }
    $null = Set-GuestNetwork
    $shelfState = Set-GuestShelf -Force:$ForceShelf
    if ($shelfState -eq 'patched') {
        # A fresh image has just received the File Manager. Restore the PC
        # backup, if there is one, so an uninstall/reinstall keeps user files.
        $null = Sync-GuestFiles -Mode Import
    }
    Update-InstalledFlag
    $script:Port = Select-FreePort
    $script:Url = "http://127.0.0.1:$Port/"
    $script:ShelfPort = Select-FreeShelfPort
    $script:ShelfUrl = "http://127.0.0.1:$ShelfPort/"
    Set-Content -Path $AppPortFile -Value $Port -Encoding ASCII
    Set-Content -Path $ShelfPortFile -Value $ShelfPort -Encoding ASCII
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
                "-netdev user,id=net0,hostfwd=tcp:127.0.0.1:${Port}-:8899,hostfwd=tcp:127.0.0.1:${ShelfPort}-:8898 -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56 " +
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
            return
        }
        Warn 'The real Flipper OS is still starting after 7 minutes.'
        if ($Shelf) {
            Write-Host "QEMU is still running. You can wait and open ${ShelfUrl}?app=$Port manually." -ForegroundColor Yellow
        } else {
            Write-Host "QEMU is still running. You can wait and open $Url manually." -ForegroundColor Yellow
        }
        Write-Host 'It keeps starting in the background. Use option 4 in this menu to stop it.' -ForegroundColor Yellow
        return
    }
    Set-Content -Path (Join-Path $RealRoot 'used.flag') -Value ((Get-Date).ToString('u')) -Encoding ASCII
    if ($Shelf) {
        $shelfReady = Test-ShelfHttp -ShelfPortToTest $ShelfPort
        if (-not $shelfReady) {
            Say 'Waiting for the File Manager ...'
            $shelfWait = [Diagnostics.Stopwatch]::StartNew()
            while ($shelfWait.Elapsed.TotalSeconds -lt 45) {
                $shelfReady = Test-ShelfHttp -ShelfPortToTest $ShelfPort
                if ($shelfReady) { break }
                Start-Sleep -Seconds 2
            }
        }
        if (-not $shelfReady) {
            Warn 'The File Manager is not answering yet. Refresh the page in a moment.'
        }
        $openUrl = "${ShelfUrl}?app=$Port"
        if (-not $NoOpen) { Start-Process $openUrl }
        Write-Host ''
        Write-Host "The real Flipper OS is running at $Url" -ForegroundColor Green
        Write-Host "File Manager: $openUrl" -ForegroundColor Green
        Write-Host 'Upload files there and test them in the App Manager right away.'
    } else {
        if (-not $NoOpen) { Start-Process $Url }
        Write-Host ''
        Write-Host "The real Flipper OS is running at $Url" -ForegroundColor Green
        Write-Host 'For your own files and apps, choose option 3 (Flipper OS + File Manager).'
    }
    Write-Host 'It keeps running in the background. Use option 4 in this menu to stop it.'
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  [1] FlipCTL preview  (fast, stable)'
        Write-Host '  [2] Real Flipper OS  (experimental, QEMU emulation)'
        Write-Host '  [3] Flipper OS + File Manager  (opens both in two browser tabs)'
        Write-Host '  [4] Stop everything'
        Write-Host '  [5] Uninstall everything'
        Write-Host '  [6] Reinstall'
        Write-Host '  [7] Show server log'
        Write-Host '  [8] Reset Flipper OS  (factory reset, deletes apps and files)'
        Write-Host '  [9] Exit'
        Write-Host '  [10] Power Meter Demo  (opens the web demo in your browser)'
        Write-Host ('  Status: ' + (Get-RunState)) -ForegroundColor DarkGray
        $c = Read-Host '  Choose an option (Enter = 1)'
        if ($null -eq $c) { return }
        $c = $c.Trim()
        if ($c -eq '') { $c = '1' }
        if ($c -notmatch '^(10|[1-9])$') { Warn 'Please enter a number from 1 to 10.'; continue }
        switch ($c) {
            '1' { Start-Demo }
            '2' { Start-RealOS }
            '3' { Open-FileShelf }
            '4' { Stop-Demo; Start-Sleep -Seconds 2 }
            '5' { $null = Uninstall-All; Start-Sleep -Seconds 3 }
            '6' { Reinstall-All }
            '7' { Show-Log }
            '8' { $null = Reset-Flipper }
            '9' { return }
            '10' { Start-Process 'https://dev.repetren.com/power_meter_demo/'; Write-Host 'Opened the Power Meter demo in your browser.' }
        }
        Write-Host ''
        $null = Read-Host 'Press Enter to return to the menu'
    }
}

# ---------------------------------------------------------------------------
# Windows app (WinForms)
# ---------------------------------------------------------------------------
$script:UiBusy          = $false
$script:UiProcess       = $null
$script:UiLogPath       = $null
$script:UiLogChars      = 0
$script:UiLogText       = ''
$script:UiAction        = ''
$script:UiActionTitle   = ''
$script:UiWork          = $null
$script:UiBat           = $null
$script:UiForm          = $null
$script:UiLogBox        = $null
$script:UiTimer         = $null
$script:UiLastStatus    = [DateTime]::MinValue
$script:UiMode          = 'one'
$script:UiOneCache      = $null
$script:ZeroCustomFirmware = ''
$script:ZeroBranch      = 'official'
$script:ZeroOfficialVersion = '1.5.1'
# Device pictures for the slider (embedded, so the app never depends on files next to it).
$script:UiImgOne  = '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'
$script:UiImgZero = 'iVBORw0KGgoAAAANSUhEUgAAAWgAAACRCAMAAADZ0dKCAAAClFBMVEXj4t309O7q6uUAAAD2gy/0exvviEXc2tXh3dfxfCjNysX9gRzOZxOxVg6TRghWJgAsKirNwrszNTf5l05zNQTS0s/Suq////8oGxIaGhm7urZoLALQdCiHPAdqSS2nSwz9kTy0qqKwhGn407f5wpi1tbJFHABGPDZXRDXIWg+uOAWvVSz5pmmsrKmqqarIyMXLaCm8vLvLpZf3yqlraGaQVyyPeGjvmmP5uYqvZCrdcBfJycV+fn6nSiaupJuvZk7We0nZhE/ibBiSKgXEmYtNSUazeWfJycTX19StmI0lIB3JyMn8olseHyDKq6PIyMfIyMXW1tLY19T6sXpZVVK5ubXIyMXo5+OnWkUODAvESAXY2NbY2Ne9YBHVmHbr6uWZSS+1clm4uLXBwr3r6uV6USySjIbEWiXl5eXl5OLp6eXs7OdsY1yIgXumLQG6jYKtrKqsq6jLim3jbS3i4dz//7H08+95cm2VPCFjXFbFbEfX19Xm5tzh4dvi4903NzcyO0KVlZWbmJPHx7rDw77a2u/f4NrhzcL19PEfICBra2udUQ2PV0Ozs6+1tbG4uMzCfGDAv77Ewr7/qqri4d8APz8oDgAgHyB9HwJ/qn9//39///+EHQCfYCyfbVOPj4+Nqo2gPyCyb2CqqpS/v3+/v7u/wLu22tqq/6rCj4nEurrMzJnFxb/d5d3d5N3f4tzjfkPlj2D/v7/h4d/k49///wD//3/09vMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADGBwv7AAAA3HRSTlP+/v4A/////v7//f////////3///+l/gL///f////////8////3v/////////dBNv/B////////////48E/////////////63O//8Q////MFKQc///LXFx////EDH//5H//3LX1f///xAtVLP/////Lk3//80D0v////9QGDJNBP8J/xW1Ef//iv8J//9RsA//3kEDiAT///8GAgL///8QCf//DASB4AcD/xoFhB4mUf//BHKwAQKwAAAA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'

# The window itself is compiled C# (custom drawn, smooth dark <-> light fade).
$script:UiSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// =============================================================================
// Flipper Emulator 8.0 - window UI (dark "One" theme <-> light "Zero" theme)
// Everything is custom painted and reads its colours from FlipTheme.Cur, so the
// whole window can fade smoothly between the two looks.
// =============================================================================

public enum FlipTone { Text, Muted, Faint, Accent, AccentText, Danger, Success, Warn }
public enum FlipRole { Bg, Side, Card, Log }
public enum FlipKind { Primary, Secondary, Danger, Ghost, Stop }

public sealed class FlipPalette
{
    public Color Bg, Side, Card, CardHover, Border, Text, Muted, Faint, Accent, AccentText;
    public Color Danger, Success, Warn, Track, LogBg, LogText, OnAccent;

    private static Color L(Color a, Color b, float t)
    {
        return Color.FromArgb(
            (int)Math.Round(a.R + (b.R - a.R) * t),
            (int)Math.Round(a.G + (b.G - a.G) * t),
            (int)Math.Round(a.B + (b.B - a.B) * t));
    }

    public static FlipPalette Lerp(FlipPalette a, FlipPalette b, float t)
    {
        FlipPalette p = new FlipPalette();
        p.Bg = L(a.Bg, b.Bg, t); p.Side = L(a.Side, b.Side, t); p.Card = L(a.Card, b.Card, t);
        p.CardHover = L(a.CardHover, b.CardHover, t); p.Border = L(a.Border, b.Border, t);
        p.Text = L(a.Text, b.Text, t); p.Muted = L(a.Muted, b.Muted, t); p.Faint = L(a.Faint, b.Faint, t);
        p.Accent = L(a.Accent, b.Accent, t); p.AccentText = L(a.AccentText, b.AccentText, t);
        p.Danger = L(a.Danger, b.Danger, t); p.Success = L(a.Success, b.Success, t); p.Warn = L(a.Warn, b.Warn, t);
        p.Track = L(a.Track, b.Track, t); p.LogBg = L(a.LogBg, b.LogBg, t); p.LogText = L(a.LogText, b.LogText, t);
        p.OnAccent = L(a.OnAccent, b.OnAccent, t);
        return p;
    }
}

public static class FlipTheme
{
    public static readonly FlipPalette Dark = MakeDark();
    public static readonly FlipPalette Light = MakeLight();
    public static FlipPalette Cur = Dark;
    public static float Amount = 0f;
    public static event EventHandler Changed;
    public static bool Animating { get { return anim != null && anim.Enabled; } }

    private static Timer anim;
    private static Stopwatch sw;
    private static float from;
    private static float to;
    private const int DurationMs = 480;

    private static FlipPalette MakeDark()
    {
        FlipPalette p = new FlipPalette();
        p.Bg = Color.FromArgb(13, 13, 13); p.Side = Color.FromArgb(20, 20, 20);
        p.Card = Color.FromArgb(28, 28, 28); p.CardHover = Color.FromArgb(40, 40, 40);
        p.Border = Color.FromArgb(51, 51, 51); p.Text = Color.FromArgb(242, 242, 242);
        p.Muted = Color.FromArgb(160, 160, 160); p.Faint = Color.FromArgb(107, 107, 107);
        p.Accent = Color.FromArgb(255, 140, 0); p.AccentText = Color.FromArgb(255, 140, 0);
        p.Danger = Color.FromArgb(229, 57, 53); p.Success = Color.FromArgb(76, 175, 80);
        p.Warn = Color.FromArgb(255, 170, 60); p.Track = Color.FromArgb(38, 38, 38);
        p.LogBg = Color.FromArgb(10, 10, 10); p.LogText = Color.FromArgb(208, 208, 208);
        p.OnAccent = Color.FromArgb(255, 255, 255);
        return p;
    }

    private static FlipPalette MakeLight()
    {
        FlipPalette p = new FlipPalette();
        p.Bg = Color.FromArgb(244, 241, 236); p.Side = Color.FromArgb(255, 255, 255);
        p.Card = Color.FromArgb(255, 255, 255); p.CardHover = Color.FromArgb(255, 246, 234);
        p.Border = Color.FromArgb(226, 219, 208); p.Text = Color.FromArgb(32, 28, 24);
        p.Muted = Color.FromArgb(110, 102, 92); p.Faint = Color.FromArgb(158, 150, 140);
        p.Accent = Color.FromArgb(255, 122, 0); p.AccentText = Color.FromArgb(226, 104, 0);
        p.Danger = Color.FromArgb(211, 47, 47); p.Success = Color.FromArgb(46, 157, 75);
        p.Warn = Color.FromArgb(230, 126, 0); p.Track = Color.FromArgb(234, 228, 219);
        p.LogBg = Color.FromArgb(250, 248, 244); p.LogText = Color.FromArgb(52, 46, 40);
        p.OnAccent = Color.FromArgb(255, 255, 255);
        return p;
    }

    public static Color Mix(Color a, Color b, float t)
    {
        return Color.FromArgb(
            (int)Math.Round(a.R + (b.R - a.R) * t),
            (int)Math.Round(a.G + (b.G - a.G) * t),
            (int)Math.Round(a.B + (b.B - a.B) * t));
    }

    public static Color ToneColor(FlipTone t)
    {
        FlipPalette p = Cur;
        switch (t)
        {
            case FlipTone.Muted: return p.Muted;
            case FlipTone.Faint: return p.Faint;
            case FlipTone.Accent: return p.Accent;
            case FlipTone.AccentText: return p.AccentText;
            case FlipTone.Danger: return p.Danger;
            case FlipTone.Success: return p.Success;
            case FlipTone.Warn: return p.Warn;
            default: return p.Text;
        }
    }

    public static Color RoleColor(FlipRole r)
    {
        FlipPalette p = Cur;
        switch (r)
        {
            case FlipRole.Side: return p.Side;
            case FlipRole.Card: return p.Card;
            case FlipRole.Log: return p.LogBg;
            default: return p.Bg;
        }
    }

    public static void SetAmount(float a)
    {
        Amount = Math.Max(0f, Math.Min(1f, a));
        Cur = FlipPalette.Lerp(Dark, Light, Amount);
        EventHandler h = Changed;
        if (h != null) { h(null, EventArgs.Empty); }
    }

    public static void AnimateTo(bool light)
    {
        if (anim == null)
        {
            anim = new Timer();
            anim.Interval = 15;
            anim.Tick += OnTick;
        }
        from = Amount;
        to = light ? 1f : 0f;
        sw = Stopwatch.StartNew();
        anim.Start();
    }

    private static void OnTick(object sender, EventArgs e)
    {
        double p = sw.ElapsedMilliseconds / (double)DurationMs;
        if (p >= 1.0) { p = 1.0; anim.Stop(); }
        double eased = p < 0.5 ? 4.0 * p * p * p : 1.0 - Math.Pow(-2.0 * p + 2.0, 3.0) / 2.0;
        SetAmount((float)(from + (to - from) * eased));
    }
}

public static class FlipNative
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void TitleBar(IntPtr handle, bool dark)
    {
        try
        {
            int v = dark ? 1 : 0;
            if (DwmSetWindowAttribute(handle, 20, ref v, sizeof(int)) != 0)
            {
                DwmSetWindowAttribute(handle, 19, ref v, sizeof(int));
            }
        }
        catch (Exception) { }
    }
}

public static class FlipImages
{
    public static Bitmap FromBase64(string b64)
    {
        try
        {
            byte[] data = Convert.FromBase64String(b64);
            using (MemoryStream ms = new MemoryStream(data))
            using (Image img = Image.FromStream(ms))
            {
                Bitmap copy = new Bitmap(img.Width, img.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(copy)) { g.DrawImage(img, 0, 0, img.Width, img.Height); }
                return copy;
            }
        }
        catch (Exception) { return null; }
    }
}

public static class FlipFonts
{
    private static readonly Dictionary<string, Font> cache = new Dictionary<string, Font>();

    public static Font Get(float size, bool semibold)
    {
        string key = size.ToString("0.##") + (semibold ? "s" : "r");
        Font f;
        if (!cache.TryGetValue(key, out f))
        {
            f = new Font(semibold ? "Segoe UI Semibold" : "Segoe UI", size, FontStyle.Regular, GraphicsUnit.Point);
            cache[key] = f;
        }
        return f;
    }

    public static Font Mono(float size)
    {
        string key = "m" + size.ToString("0.##");
        Font f;
        if (!cache.TryGetValue(key, out f))
        {
            f = new Font("Consolas", size, FontStyle.Regular, GraphicsUnit.Point);
            cache[key] = f;
        }
        return f;
    }
}

public static class FlipDraw
{
    public static GraphicsPath Round(RectangleF r, float radius)
    {
        GraphicsPath p = new GraphicsPath();
        float d = Math.Min(radius * 2f, Math.Min(r.Width, r.Height));
        if (d < 1f) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public static void Text(Graphics g, string text, Font font, Rectangle r, Color c, TextFormatFlags flags)
    {
        TextRenderer.DrawText(g, text, font, r, c, flags | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
    }

    // Vector icons, drawn centred on (cx, cy) inside a square of the given size.
    public static void Icon(Graphics g, string name, float cx, float cy, float size, Color c)
    {
        SmoothingMode old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float s = size;
        float x0 = cx - s / 2f;
        float y0 = cy - s / 2f;
        float lw = Math.Max(1.6f, s / 11f);
        using (Pen pen = new Pen(c, lw))
        using (SolidBrush br = new SolidBrush(c))
        {
            pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
            switch (name)
            {
                case "play":
                    g.FillPolygon(br, new PointF[] { new PointF(x0 + s * 0.22f, y0 + s * 0.12f), new PointF(x0 + s * 0.88f, y0 + s * 0.5f), new PointF(x0 + s * 0.22f, y0 + s * 0.88f) });
                    break;
                case "stop":
                    using (GraphicsPath p = Round(new RectangleF(x0 + s * 0.18f, y0 + s * 0.18f, s * 0.64f, s * 0.64f), s * 0.1f)) { g.FillPath(br, p); }
                    break;
                case "bolt":
                    g.FillPolygon(br, new PointF[] {
                        new PointF(x0 + s * 0.58f, y0 + s * 0.04f), new PointF(x0 + s * 0.2f, y0 + s * 0.56f), new PointF(x0 + s * 0.46f, y0 + s * 0.56f),
                        new PointF(x0 + s * 0.38f, y0 + s * 0.96f), new PointF(x0 + s * 0.8f, y0 + s * 0.4f), new PointF(x0 + s * 0.54f, y0 + s * 0.4f) });
                    break;
                case "os":
                    using (GraphicsPath p = Round(new RectangleF(x0 + s * 0.2f, y0 + s * 0.2f, s * 0.6f, s * 0.6f), s * 0.1f)) { g.DrawPath(pen, p); }
                    g.DrawRectangle(pen, x0 + s * 0.38f, y0 + s * 0.38f, s * 0.24f, s * 0.24f);
                    for (int i = 0; i < 3; i++)
                    {
                        float t = 0.34f + i * 0.16f;
                        g.DrawLine(pen, x0 + s * t, y0 + s * 0.06f, x0 + s * t, y0 + s * 0.2f);
                        g.DrawLine(pen, x0 + s * t, y0 + s * 0.8f, x0 + s * t, y0 + s * 0.94f);
                        g.DrawLine(pen, x0 + s * 0.06f, y0 + s * t, x0 + s * 0.2f, y0 + s * t);
                        g.DrawLine(pen, x0 + s * 0.8f, y0 + s * t, x0 + s * 0.94f, y0 + s * t);
                    }
                    break;
                case "preview":
                    using (GraphicsPath p = Round(new RectangleF(x0 + s * 0.08f, y0 + s * 0.18f, s * 0.84f, s * 0.64f), s * 0.1f)) { g.DrawPath(pen, p); }
                    g.DrawLine(pen, x0 + s * 0.08f, y0 + s * 0.36f, x0 + s * 0.92f, y0 + s * 0.36f);
                    g.FillEllipse(br, x0 + s * 0.17f, y0 + s * 0.255f, s * 0.06f, s * 0.06f);
                    g.FillEllipse(br, x0 + s * 0.28f, y0 + s * 0.255f, s * 0.06f, s * 0.06f);
                    break;
                case "folder":
                    g.DrawPolygon(pen, new PointF[] {
                        new PointF(x0 + s * 0.08f, y0 + s * 0.24f), new PointF(x0 + s * 0.38f, y0 + s * 0.24f), new PointF(x0 + s * 0.48f, y0 + s * 0.36f),
                        new PointF(x0 + s * 0.92f, y0 + s * 0.36f), new PointF(x0 + s * 0.92f, y0 + s * 0.8f), new PointF(x0 + s * 0.08f, y0 + s * 0.8f) });
                    break;
                case "log":
                    g.DrawLine(pen, x0 + s * 0.14f, y0 + s * 0.28f, x0 + s * 0.86f, y0 + s * 0.28f);
                    g.DrawLine(pen, x0 + s * 0.14f, y0 + s * 0.5f, x0 + s * 0.7f, y0 + s * 0.5f);
                    g.DrawLine(pen, x0 + s * 0.14f, y0 + s * 0.72f, x0 + s * 0.78f, y0 + s * 0.72f);
                    break;
                case "reset":
                    g.DrawArc(pen, x0 + s * 0.16f, y0 + s * 0.16f, s * 0.68f, s * 0.68f, -40, -280);
                    g.FillPolygon(br, new PointF[] { new PointF(x0 + s * 0.18f, y0 + s * 0.12f), new PointF(x0 + s * 0.18f, y0 + s * 0.46f), new PointF(x0 + s * 0.46f, y0 + s * 0.3f) });
                    break;
                case "reinstall":
                    g.DrawArc(pen, x0 + s * 0.16f, y0 + s * 0.16f, s * 0.68f, s * 0.68f, 140, 280);
                    g.FillPolygon(br, new PointF[] { new PointF(x0 + s * 0.82f, y0 + s * 0.88f), new PointF(x0 + s * 0.82f, y0 + s * 0.54f), new PointF(x0 + s * 0.54f, y0 + s * 0.7f) });
                    break;
                case "trash":
                    g.DrawLine(pen, x0 + s * 0.14f, y0 + s * 0.26f, x0 + s * 0.86f, y0 + s * 0.26f);
                    g.DrawLine(pen, x0 + s * 0.38f, y0 + s * 0.26f, x0 + s * 0.38f, y0 + s * 0.14f);
                    g.DrawLine(pen, x0 + s * 0.38f, y0 + s * 0.14f, x0 + s * 0.62f, y0 + s * 0.14f);
                    g.DrawLine(pen, x0 + s * 0.62f, y0 + s * 0.14f, x0 + s * 0.62f, y0 + s * 0.26f);
                    g.DrawPolygon(pen, new PointF[] { new PointF(x0 + s * 0.22f, y0 + s * 0.26f), new PointF(x0 + s * 0.28f, y0 + s * 0.88f), new PointF(x0 + s * 0.72f, y0 + s * 0.88f), new PointF(x0 + s * 0.78f, y0 + s * 0.26f) });
                    g.DrawLine(pen, x0 + s * 0.42f, y0 + s * 0.42f, x0 + s * 0.43f, y0 + s * 0.72f);
                    g.DrawLine(pen, x0 + s * 0.58f, y0 + s * 0.42f, x0 + s * 0.57f, y0 + s * 0.72f);
                    break;
                case "download":
                    g.DrawLine(pen, x0 + s * 0.5f, y0 + s * 0.12f, x0 + s * 0.5f, y0 + s * 0.6f);
                    g.DrawLine(pen, x0 + s * 0.3f, y0 + s * 0.42f, x0 + s * 0.5f, y0 + s * 0.62f);
                    g.DrawLine(pen, x0 + s * 0.7f, y0 + s * 0.42f, x0 + s * 0.5f, y0 + s * 0.62f);
                    g.DrawLine(pen, x0 + s * 0.14f, y0 + s * 0.86f, x0 + s * 0.86f, y0 + s * 0.86f);
                    break;
                case "display":
                    using (GraphicsPath p = Round(new RectangleF(x0 + s * 0.1f, y0 + s * 0.16f, s * 0.8f, s * 0.54f), s * 0.08f)) { g.DrawPath(pen, p); }
                    g.DrawLine(pen, x0 + s * 0.5f, y0 + s * 0.7f, x0 + s * 0.5f, y0 + s * 0.84f);
                    g.DrawLine(pen, x0 + s * 0.3f, y0 + s * 0.86f, x0 + s * 0.7f, y0 + s * 0.86f);
                    break;
                case "check":
                    g.DrawLine(pen, x0 + s * 0.2f, y0 + s * 0.54f, x0 + s * 0.42f, y0 + s * 0.74f);
                    g.DrawLine(pen, x0 + s * 0.42f, y0 + s * 0.74f, x0 + s * 0.82f, y0 + s * 0.28f);
                    break;
                case "cross":
                    g.DrawLine(pen, x0 + s * 0.24f, y0 + s * 0.24f, x0 + s * 0.76f, y0 + s * 0.76f);
                    g.DrawLine(pen, x0 + s * 0.76f, y0 + s * 0.24f, x0 + s * 0.24f, y0 + s * 0.76f);
                    break;
            }
        }
        g.SmoothingMode = old;
    }
}

// ----------------------------------------------------------------------------
// Basic building blocks
// ----------------------------------------------------------------------------
public class FlipSurface : Panel
{
    public FlipRole Role = FlipRole.Bg;
    public FlipRole Backdrop = FlipRole.Bg;
    public bool Rounded;
    public bool Bordered;
    public int Radius = 12;

    public FlipSurface()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; }
        base.Dispose(disposing);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        if (!Rounded)
        {
            using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Role))) { g.FillRectangle(b, ClientRectangle); }
            return;
        }
        using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Backdrop))) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath path = FlipDraw.Round(r, Radius))
        using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Role)))
        {
            g.FillPath(b, path);
            if (Bordered)
            {
                using (Pen pen = new Pen(p.Border, 1f)) { g.DrawPath(pen, path); }
            }
        }
    }
}

public class FlipLabel : Label
{
    public FlipTone Tone = FlipTone.Text;

    public FlipLabel()
    {
        AutoSize = false;
        BackColor = Color.Transparent;
        UseMnemonic = false;
        FlipTheme.Changed += OnTheme;
        ForeColor = FlipTheme.ToneColor(Tone);
    }

    public void SetTone(FlipTone t)
    {
        Tone = t;
        ForeColor = FlipTheme.ToneColor(t);
    }

    private void OnTheme(object s, EventArgs e) { ForeColor = FlipTheme.ToneColor(Tone); }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; }
        base.Dispose(disposing);
    }
}

public class FlipPicture : Control
{
    public Image Img;

    public FlipPicture()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (Img == null) { return; }
        Graphics g = e.Graphics;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        float sc = Math.Min(Width / (float)Img.Width, Height / (float)Img.Height);
        float w = Img.Width * sc;
        float h = Img.Height * sc;
        g.DrawImage(Img, (Width - w) / 2f, (Height - h) / 2f, w, h);
    }
}

public class FlipButton : Control
{
    public FlipKind Kind = FlipKind.Secondary;
    public string IconName = "";
    public FlipRole Backdrop = FlipRole.Card;
    public float FontSize = 9.5f;
    private bool hover;
    private bool down;

    public FlipButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        Cursor = Cursors.Hand;
        Height = 34;
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; }
        base.Dispose(disposing);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { down = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Backdrop))) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color fill, border, text;
        bool hot = hover && Enabled;
        switch (Kind)
        {
            case FlipKind.Primary:
                fill = hot ? FlipTheme.Mix(p.Accent, Color.White, 0.12f) : p.Accent;
                if (down) { fill = FlipTheme.Mix(p.Accent, Color.Black, 0.12f); }
                border = fill; text = p.OnAccent; break;
            case FlipKind.Stop:
                fill = hot ? FlipTheme.Mix(p.Danger, Color.White, 0.1f) : p.Danger;
                if (down) { fill = FlipTheme.Mix(p.Danger, Color.Black, 0.12f); }
                border = fill; text = Color.White; break;
            case FlipKind.Danger:
                fill = hot ? p.Danger : FlipTheme.Mix(p.Card, p.Danger, 0.08f);
                border = p.Danger; text = hot ? Color.White : p.Danger; break;
            case FlipKind.Ghost:
                fill = hot ? p.CardHover : FlipTheme.RoleColor(Backdrop);
                border = p.Border; text = hot ? p.Text : p.Muted; break;
            default:
                fill = hot ? p.CardHover : p.Track;
                border = hot ? p.Accent : p.Border; text = p.Text; break;
        }
        if (!Enabled)
        {
            fill = FlipTheme.Mix(p.Track, FlipTheme.RoleColor(Backdrop), 0.35f);
            border = p.Border; text = p.Faint;
        }
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath path = FlipDraw.Round(r, 9))
        using (SolidBrush b = new SolidBrush(fill))
        using (Pen pen = new Pen(border, 1f))
        {
            g.FillPath(b, path);
            g.DrawPath(pen, path);
        }
        Font f = FlipFonts.Get(FontSize, true);
        Size ts = TextRenderer.MeasureText(Text, f);
        bool hasIcon = IconName != null && IconName.Length > 0;
        float iconSize = Math.Min(Height * 0.5f, 22f);
        float total = ts.Width + (hasIcon ? iconSize + 8f : 0f);
        float x = (Width - total) / 2f;
        if (hasIcon)
        {
            FlipDraw.Icon(g, IconName, x + iconSize / 2f, Height / 2f, iconSize, text);
            x += iconSize + 8f;
        }
        FlipDraw.Text(g, Text, f, new Rectangle((int)x, 0, ts.Width + 4, Height), text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
    }
}

// Action card: icon, title, description and an optional checkbox row.
public class FlipCard : Control
{
    public string Title = "";
    public string Desc = "";
    public string IconName = "";
    public FlipTone ToneKey = FlipTone.Accent;
    public bool Featured;
    public string OptionText = "";
    public bool OptionChecked;
    public FlipRole Backdrop = FlipRole.Bg;
    public string ActionKey = "";
    public event EventHandler ActionClicked;
    public event EventHandler OptionToggled;
    private bool hover;
    private bool down;
    private bool overOption;

    public FlipCard()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        Cursor = Cursors.Hand;
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; }
        base.Dispose(disposing);
    }

    private Rectangle OptionRect()
    {
        if (OptionText == null || OptionText.Length == 0) { return Rectangle.Empty; }
        Size ts = TextRenderer.MeasureText(OptionText, FlipFonts.Get(8.75f, false));
        return new Rectangle(14, Height - 38, 16 + 8 + ts.Width + 12 + 14, 28);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; overOption = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        bool o = OptionRect().Contains(e.Location);
        if (o != overOption) { overOption = o; Invalidate(); }
        base.OnMouseMove(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { down = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        bool wasDown = down;
        down = false;
        Invalidate();
        base.OnMouseUp(e);
        if (!wasDown || e.Button != MouseButtons.Left || !Enabled) { return; }
        if (!ClientRectangle.Contains(e.Location)) { return; }
        if (OptionRect().Contains(e.Location))
        {
            OptionChecked = !OptionChecked;
            Invalidate();
            EventHandler h = OptionToggled;
            if (h != null) { h(this, EventArgs.Empty); }
            return;
        }
        EventHandler a = ActionClicked;
        if (a != null) { a(this, EventArgs.Empty); }
    }
    protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; if (!Enabled) { hover = false; } Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Backdrop))) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color tone = FlipTheme.ToneColor(ToneKey);
        bool hot = hover && Enabled;
        Color fill = hot ? p.CardHover : p.Card;
        if (Featured) { fill = FlipTheme.Mix(fill, p.Accent, hot ? 0.10f : 0.06f); }
        if (down && Enabled) { fill = FlipTheme.Mix(fill, Color.Black, 0.06f); }
        Color border = hot ? tone : (Featured ? FlipTheme.Mix(p.Border, p.Accent, 0.55f) : p.Border);
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath path = FlipDraw.Round(r, 12))
        using (SolidBrush b = new SolidBrush(fill))
        using (Pen pen = new Pen(border, Featured ? 1.5f : 1f))
        {
            g.FillPath(b, path);
            g.DrawPath(pen, path);
        }
        Color shown = Enabled ? tone : p.Faint;
        // icon badge
        float ib = 42f;
        RectangleF ibr = new RectangleF(16f, 16f, ib, ib);
        using (GraphicsPath ip = FlipDraw.Round(ibr, 11))
        using (SolidBrush b = new SolidBrush(FlipTheme.Mix(fill, shown, Enabled ? 0.16f : 0.06f)))
        {
            g.FillPath(b, ip);
        }
        if (IconName != null && IconName.Length > 0) { FlipDraw.Icon(g, IconName, 16f + ib / 2f, 16f + ib / 2f, 22f, shown); }
        // text
        Color titleC = Enabled ? p.Text : p.Faint;
        Color descC = Enabled ? p.Muted : p.Faint;
        int tx = 16 + (int)ib + 14;
        FlipDraw.Text(g, Title, FlipFonts.Get(11.5f, true), new Rectangle(tx, 15, Width - tx - 34, 24), titleC, TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter);
        bool hasOption = OptionText != null && OptionText.Length > 0;
        int descH = Height - 44 - (hasOption ? 40 : 14);
        FlipDraw.Text(g, Desc, FlipFonts.Get(8.75f, false), new Rectangle(tx, 42, Width - tx - 16, Math.Max(20, descH + 6)), descC, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak);
        // chevron
        using (Pen cp = new Pen(hot ? tone : p.Faint, 1.8f))
        {
            cp.StartCap = LineCap.Round; cp.EndCap = LineCap.Round;
            float cx = Width - 20f; float cy = 27f;
            g.DrawLine(cp, cx - 3f, cy - 5f, cx + 2f, cy);
            g.DrawLine(cp, cx + 2f, cy, cx - 3f, cy + 5f);
        }
        // option row (checkbox)
        if (hasOption)
        {
            Rectangle or = OptionRect();
            bool oh = overOption && Enabled;
            using (GraphicsPath op = FlipDraw.Round(new RectangleF(or.X, or.Y, or.Width, or.Height), 8))
            using (SolidBrush b = new SolidBrush(oh ? FlipTheme.Mix(fill, tone, 0.14f) : FlipTheme.Mix(fill, p.Track, 0.8f)))
            using (Pen bp = new Pen(oh ? tone : p.Border, 1f))
            {
                g.FillPath(b, op);
                g.DrawPath(bp, op);
            }
            RectangleF box = new RectangleF(or.X + 8, or.Y + 6, 16, 16);
            using (GraphicsPath bx = FlipDraw.Round(box, 4))
            {
                if (OptionChecked)
                {
                    using (SolidBrush b = new SolidBrush(Enabled ? p.Accent : p.Faint)) { g.FillPath(b, bx); }
                    FlipDraw.Icon(g, "check", box.X + 8, box.Y + 8, 14, Color.White);
                }
                else
                {
                    using (Pen bp = new Pen(p.Muted, 1.4f)) { g.DrawPath(bp, bx); }
                }
            }
            FlipDraw.Text(g, OptionText, FlipFonts.Get(8.75f, false), new Rectangle(or.X + 32, or.Y, or.Width - 34, or.Height), Enabled ? p.Text : p.Faint, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }
}

public class FlipSegment : Control
{
    public string[] Items = new string[0];
    private int selected;
    public event EventHandler SelectedChanged;
    private int hoverIndex = -1;

    public FlipSegment()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
        Height = 38;
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }
    protected override void Dispose(bool disposing) { if (disposing) { FlipTheme.Changed -= OnTheme; } base.Dispose(disposing); }

    public int SelectedIndex
    {
        get { return selected; }
        set { if (value == selected) { return; } selected = value; Invalidate(); }
    }

    private int Hit(int x)
    {
        if (Items.Length == 0) { return -1; }
        int i = (int)((x - 3) / ((Width - 6) / (float)Items.Length));
        return Math.Max(0, Math.Min(Items.Length - 1, i));
    }

    protected override void OnMouseMove(MouseEventArgs e) { int h = Hit(e.X); if (h != hoverIndex) { hoverIndex = h; Invalidate(); } base.OnMouseMove(e); }
    protected override void OnMouseLeave(EventArgs e) { hoverIndex = -1; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (!Enabled || e.Button != MouseButtons.Left) { return; }
        int i = Hit(e.X);
        if (i < 0 || i == selected) { return; }
        selected = i;
        Invalidate();
        EventHandler h = SelectedChanged;
        if (h != null) { h(this, EventArgs.Empty); }
    }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(p.Card)) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2, Height - 2);
        using (GraphicsPath tp = FlipDraw.Round(r, Height / 2f))
        using (SolidBrush b = new SolidBrush(p.Track))
        using (Pen pen = new Pen(p.Border, 1f))
        {
            g.FillPath(b, tp);
            g.DrawPath(pen, tp);
        }
        if (Items.Length == 0) { return; }
        float sw = (Width - 6) / (float)Items.Length;
        for (int i = 0; i < Items.Length; i++)
        {
            RectangleF seg = new RectangleF(3 + i * sw, 3, sw, Height - 6);
            bool sel = (i == selected);
            if (sel)
            {
                using (GraphicsPath sp = FlipDraw.Round(seg, (Height - 6) / 2f))
                using (SolidBrush b = new SolidBrush(Enabled ? p.Accent : p.Faint)) { g.FillPath(b, sp); }
            }
            Color c = sel ? p.OnAccent : (i == hoverIndex && Enabled ? p.Text : p.Muted);
            if (!Enabled && !sel) { c = p.Faint; }
            FlipDraw.Text(g, Items[i], FlipFonts.Get(9.25f, true), new Rectangle((int)seg.X, (int)seg.Y, (int)seg.Width, (int)seg.Height), c, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }
}

public class FlipBadge : Control
{
    public string Caption = "";
    public FlipTone ToneKey = FlipTone.Faint;
    public FlipRole Backdrop = FlipRole.Card;

    public FlipBadge()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 26;
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }
    protected override void Dispose(bool disposing) { if (disposing) { FlipTheme.Changed -= OnTheme; } base.Dispose(disposing); }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    public int PreferredWidth()
    {
        return TextRenderer.MeasureText(Caption, FlipFonts.Get(8.5f, true)).Width + 38;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(FlipTheme.RoleColor(Backdrop))) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color tone = FlipTheme.ToneColor(ToneKey);
        using (GraphicsPath path = FlipDraw.Round(new RectangleF(0.5f, 0.5f, Width - 2, Height - 2), Height / 2f))
        using (SolidBrush b = new SolidBrush(FlipTheme.Mix(FlipTheme.RoleColor(Backdrop), tone, 0.14f)))
        {
            g.FillPath(b, path);
        }
        using (SolidBrush b = new SolidBrush(tone)) { g.FillEllipse(b, 11, Height / 2f - 4f, 8, 8); }
        FlipDraw.Text(g, Caption, FlipFonts.Get(8.5f, true), new Rectangle(26, 0, Width - 28, Height), tone, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
    }
}

public sealed class FlipProgress : Control
{
    private int value;
    private int maximum = 100;
    private bool marquee;
    private int marqueeOffset;

    public int Value { get { return value; } set { this.value = Math.Max(0, Math.Min(maximum, value)); Invalidate(); } }
    public int Maximum { get { return maximum; } set { maximum = Math.Max(1, value); Invalidate(); } }
    private Timer spin;
    public bool Marquee
    {
        get { return marquee; }
        set
        {
            marquee = value;
            if (value) { spin.Start(); } else { spin.Stop(); }
            Invalidate();
        }
    }
    public int MarqueeOffset { get { return marqueeOffset; } set { marqueeOffset = value; Invalidate(); } }

    public FlipProgress()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 8;
        spin = new Timer();
        spin.Interval = 30;
        spin.Tick += delegate { marqueeOffset += 7; if (Visible) { Invalidate(); } };
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }
    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; spin.Stop(); spin.Dispose(); }
        base.Dispose(disposing);
    }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(p.Card)) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF r = new RectangleF(0, 0, Width - 1, Height - 1);
        using (GraphicsPath path = FlipDraw.Round(r, Height / 2f))
        using (SolidBrush b = new SolidBrush(p.Track)) { g.FillPath(b, path); }
        if (marquee)
        {
            int bw = Math.Max(24, Width / 5);
            int x = marqueeOffset % (Width + bw) - bw;
            RectangleF fr = new RectangleF(Math.Max(0, x), 0, Math.Min(bw, Math.Min(x + bw, Width - Math.Max(0, x))), Height - 1);
            if (fr.Width > 2)
            {
                using (GraphicsPath fp = FlipDraw.Round(fr, Height / 2f))
                using (SolidBrush b = new SolidBrush(p.Accent)) { g.FillPath(b, fp); }
            }
        }
        else
        {
            int fw = (int)((double)value / maximum * (Width - 1));
            if (fw > 2)
            {
                using (GraphicsPath fp = FlipDraw.Round(new RectangleF(0, 0, fw, Height - 1), Height / 2f))
                using (SolidBrush b = new SolidBrush(p.Accent)) { g.FillPath(b, fp); }
            }
        }
    }
}

// Slider that switches between the Flipper One (left) and Flipper Zero (right).
public sealed class FlipToggle : Control
{
    public Bitmap ImgOne;
    public Bitmap ImgZero;
    private bool isZero;
    private float pos;          // 0 = left (One), 1 = right (Zero)
    private float target;
    private Timer timer;
    private Stopwatch sw;
    private float startPos;
    private bool hover;
    public event EventHandler Toggled;

    public FlipToggle()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
        Size = new Size(224, 72);
        FlipTheme.Changed += OnTheme;
    }

    private void OnTheme(object s, EventArgs e) { Invalidate(); }
    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; if (timer != null) { timer.Dispose(); } }
        base.Dispose(disposing);
    }

    public bool IsZero
    {
        get { return isZero; }
        set { SetZero(value, true, false); }
    }

    public void SetZero(bool zero, bool animate, bool raise)
    {
        if (zero == isZero && Math.Abs(pos - (zero ? 1f : 0f)) < 0.001f) { return; }
        isZero = zero;
        target = zero ? 1f : 0f;
        if (!animate)
        {
            pos = target;
            Invalidate();
        }
        else
        {
            if (timer == null) { timer = new Timer(); timer.Interval = 12; timer.Tick += OnTick; }
            startPos = pos;
            sw = Stopwatch.StartNew();
            timer.Start();
        }
        if (raise)
        {
            EventHandler h = Toggled;
            if (h != null) { h(this, EventArgs.Empty); }
        }
    }

    private void OnTick(object s, EventArgs e)
    {
        double t = sw.ElapsedMilliseconds / 260.0;
        if (t >= 1.0) { t = 1.0; timer.Stop(); }
        double eased = 1.0 - Math.Pow(1.0 - t, 3.0);
        pos = (float)(startPos + (target - startPos) * eased);
        Invalidate();
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left) { return; }
        bool wantZero = e.X >= Width / 2;
        if (wantZero != isZero) { SetZero(wantZero, true, true); }
    }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        FlipPalette p = FlipTheme.Cur;
        using (SolidBrush b = new SolidBrush(p.Side)) { g.FillRectangle(b, ClientRectangle); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        int w = Width, h = Height;
        RectangleF tr = new RectangleF(0.5f, 0.5f, w - 2, h - 2);
        using (GraphicsPath track = FlipDraw.Round(tr, h / 2f))
        using (SolidBrush b = new SolidBrush(p.Track))
        using (Pen pen = new Pen(hover ? p.Accent : p.Border, 1f))
        {
            g.FillPath(b, track);
            g.DrawPath(pen, track);
        }
        // side captions
        Rectangle left = new Rectangle(0, 0, w / 2, h);
        Rectangle right = new Rectangle(w / 2, 0, w / 2, h);
        FlipDraw.Text(g, "ONE", FlipFonts.Get(9f, true), left, p.Faint, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        FlipDraw.Text(g, "ZERO", FlipFonts.Get(9f, true), right, p.Faint, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        // thumb
        float thumbW = w * 0.66f;
        float thumbH = h - 8f;
        float x = 4f + (w - thumbW - 8f) * pos;
        RectangleF thumb = new RectangleF(x, 4f, thumbW, thumbH);
        using (GraphicsPath tp = FlipDraw.Round(thumb, thumbH / 2f))
        using (LinearGradientBrush lg = new LinearGradientBrush(thumb, Color.FromArgb(255, 170, 50), Color.FromArgb(255, 122, 0), LinearGradientMode.Vertical))
        {
            g.FillPath(lg, tp);
        }
        // device picture inside the thumb: blend from One to Zero around the middle
        Bitmap a = ImgOne;
        Bitmap bz = ImgZero;
        float zeroAlpha = Math.Max(0f, Math.Min(1f, (pos - 0.25f) / 0.5f));
        RectangleF box = new RectangleF(thumb.X + thumbH * 0.26f, thumb.Y + 4f, thumb.Width - thumbH * 0.52f, thumb.Height - 8f);
        DrawFit(g, a, box, 1f - zeroAlpha);
        DrawFit(g, bz, box, zeroAlpha);
    }

    private static void DrawFit(Graphics g, Bitmap img, RectangleF box, float alpha)
    {
        if (img == null || alpha <= 0.01f) { return; }
        float sc = Math.Min(box.Width / img.Width, box.Height / img.Height);
        float iw = img.Width * sc;
        float ih = img.Height * sc;
        RectangleF dest = new RectangleF(box.X + (box.Width - iw) / 2f, box.Y + (box.Height - ih) / 2f, iw, ih);
        using (System.Drawing.Imaging.ImageAttributes ia = new System.Drawing.Imaging.ImageAttributes())
        {
            float[][] m = new float[][] {
                new float[] { 1, 0, 0, 0, 0 }, new float[] { 0, 1, 0, 0, 0 }, new float[] { 0, 0, 1, 0, 0 },
                new float[] { 0, 0, 0, alpha, 0 }, new float[] { 0, 0, 0, 0, 1 } };
            ia.SetColorMatrix(new System.Drawing.Imaging.ColorMatrix(m));
            g.DrawImage(img, new Rectangle((int)dest.X, (int)dest.Y, (int)Math.Ceiling(dest.Width), (int)Math.Ceiling(dest.Height)), 0, 0, img.Width, img.Height, GraphicsUnit.Pixel, ia);
        }
    }
}

// ----------------------------------------------------------------------------
// Themed confirmation dialog (typed phrase)
// ----------------------------------------------------------------------------
public sealed class FlipConfirmDialog : Form
{
    public static bool Confirm(IWin32Window owner, string title, string heading, string body,
        string phrase, string confirmLabel, FlipTone tone, bool caseSensitive)
    {
        using (FlipConfirmDialog d = new FlipConfirmDialog(title, heading, body, phrase, confirmLabel, tone, caseSensitive))
        {
            return d.ShowDialog(owner) == DialogResult.OK;
        }
    }

    private FlipConfirmDialog(string title, string heading, string body, string phrase, string confirmLabel, FlipTone tone, bool caseSensitive)
    {
        FlipPalette p = FlipTheme.Cur;
        Color accent = FlipTheme.ToneColor(tone);
        Text = title;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false; ShowIcon = false;
        BackColor = p.Bg; ForeColor = p.Text;
        Font = FlipFonts.Get(9.5f, false);
        int bodyH = TextRenderer.MeasureText(body, FlipFonts.Get(9.25f, false), new Size(496, 2000), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height + 6;
        int y = 24;
        ClientSize = new Size(548, 24 + 34 + bodyH + 14 + 24 + 34 + 26 + 54 + 22);

        Panel bar = new Panel(); bar.Dock = DockStyle.Top; bar.Height = 4; bar.BackColor = accent;
        Label hl = new Label(); hl.Text = heading; hl.Font = FlipFonts.Get(16f, true); hl.ForeColor = p.Text; hl.BackColor = p.Bg; hl.SetBounds(26, y, 496, 32);
        y += 38;
        Label bl = new Label(); bl.Text = body; bl.Font = FlipFonts.Get(9.25f, false); bl.ForeColor = p.Muted; bl.BackColor = p.Bg; bl.UseMnemonic = false; bl.SetBounds(26, y, 496, bodyH);
        y += bodyH + 14;
        Label pl = new Label(); pl.Text = "Type " + phrase + " to continue"; pl.Font = FlipFonts.Get(9.5f, true); pl.ForeColor = accent; pl.BackColor = p.Bg; pl.UseMnemonic = false; pl.SetBounds(26, y, 496, 22);
        y += 26;
        TextBox tb = new TextBox(); tb.SetBounds(26, y, 496, 30); tb.BackColor = p.LogBg; tb.ForeColor = p.Text; tb.BorderStyle = BorderStyle.FixedSingle; tb.Font = FlipFonts.Mono(12f);
        y += 40;
        Label hint = new Label(); hint.Text = "The button becomes available when the word matches."; hint.Font = FlipFonts.Get(8.25f, false); hint.ForeColor = p.Faint; hint.BackColor = p.Bg; hint.SetBounds(26, y, 496, 20);
        y += 36;

        Button cancel = new Button(); cancel.Text = "Cancel"; cancel.SetBounds(244, y, 106, 36);
        cancel.FlatStyle = FlatStyle.Flat; cancel.UseVisualStyleBackColor = false; cancel.BackColor = p.Track; cancel.ForeColor = p.Text;
        cancel.FlatAppearance.BorderColor = p.Border; cancel.FlatAppearance.BorderSize = 1; cancel.DialogResult = DialogResult.Cancel; cancel.Cursor = Cursors.Hand;
        Button ok = new Button(); ok.Text = confirmLabel; ok.SetBounds(362, y, 160, 36);
        ok.FlatStyle = FlatStyle.Flat; ok.UseVisualStyleBackColor = false; ok.BackColor = p.Track; ok.ForeColor = p.Faint; ok.FlatAppearance.BorderSize = 0; ok.Enabled = false;
        ok.Click += delegate { if (ok.Enabled) { DialogResult = DialogResult.OK; Close(); } };
        tb.TextChanged += delegate
        {
            bool match = caseSensitive ? string.Equals(tb.Text, phrase, StringComparison.Ordinal) : string.Equals(tb.Text, phrase, StringComparison.OrdinalIgnoreCase);
            ok.Enabled = match;
            ok.BackColor = match ? accent : p.Track;
            ok.ForeColor = match ? Color.White : p.Faint;
            ok.Cursor = match ? Cursors.Hand : Cursors.Default;
        };
        AcceptButton = ok; CancelButton = cancel;
        Controls.Add(bar); Controls.Add(hl); Controls.Add(bl); Controls.Add(pl); Controls.Add(tb); Controls.Add(hint); Controls.Add(cancel); Controls.Add(ok);
        Shown += delegate { FlipNative.TitleBar(Handle, FlipTheme.Amount < 0.5f); tb.Focus(); };
    }
}

// ----------------------------------------------------------------------------
// Main window
// ----------------------------------------------------------------------------
public sealed class FlipperMainForm : Form
{
    // ---- public API used by the PowerShell side ----
    public event EventHandler ActionRequested;
    public event EventHandler ModeChanged;
    public event EventHandler FirmwareChanged;
    public string RequestedAction = "";
    public TextBox LogBox;
    public FlipProgress Progress;
    public bool OpenFileManager { get { return cardReal.OptionChecked; } }
    public bool IsZeroMode { get { return zeroMode; } }
    public int FirmwareIndex { get { return segFirmware.SelectedIndex; } set { segFirmware.SelectedIndex = value; UpdateZeroLayoutState(); } }

    private string version;
    private bool zeroMode;
    private bool busy;
    private bool zInstalled;
    private bool zRunning;
    private string customName = "";
    private string officialLabel = "Official";

    // chrome
    private FlipSurface side, main, pageHost, pageOne, pageZero, activity, logWrap, statusCard, hero, launcher;
    private FlipToggle toggle;
    private FlipLabel lblBrand, lblVersion, lblTag, lblStatusDot, lblStatusTitle, lblStatusDetail, lblLive;
    private FlipLabel lblSvcHead, lblSvc1, lblSvc2, lblSvc3, lblFooter;
    private FlipLabel lblTitle, lblSub;
    private FlipButton btnRefresh, btnExit;
    // one page
    private FlipLabel gStart, gManage, gMaint;
    private FlipCard cardReal, cardPreview, cardPower, cardStop, cardLog, cardBackup, cardReset, cardReinstall, cardWipe;
    // zero page
    private FlipLabel zHeroTitle, zHeroDesc, zLaunchHead, zFwLabel, zCustomName, zHint, zMaint;
    private FlipPicture zPic;
    private FlipBadge zBadge;
    private FlipButton zInstall, zStart, zDisplay, zBrowse;
    private FlipSegment segFirmware;
    private FlipCard zReset, zWipe;
    // activity
    private FlipLabel lblActivity, lblActState;
    private FlipButton btnClear, btnCancel;
    private List<Control> interactive = new List<Control>();

    private const int SideW = 272;

    public FlipperMainForm(string versionText, Bitmap imgOne, Bitmap imgZero)
    {
        version = versionText;
        SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        Text = "Flipper Emulator " + versionText;
        ClientSize = new Size(1140, 760);
        MinimumSize = new Size(1000, 660);
        StartPosition = FormStartPosition.CenterScreen;
        Font = FlipFonts.Get(9f, false);
        KeyPreview = true;
        BackColor = FlipTheme.Cur.Bg;
        FlipTheme.Changed += OnTheme;

        BuildSide(imgOne, imgZero);
        BuildMain(imgZero);
        Resize += delegate { LayoutAll(); };
        Shown += delegate { FlipNative.TitleBar(Handle, FlipTheme.Amount < 0.5f); };
        LayoutAll();
        SetMode(false, false);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { FlipTheme.Changed -= OnTheme; }
        base.Dispose(disposing);
    }

    private void OnTheme(object s, EventArgs e)
    {
        BackColor = FlipTheme.Cur.Bg;
        if (LogBox != null) { LogBox.BackColor = FlipTheme.Cur.LogBg; LogBox.ForeColor = FlipTheme.Cur.LogText; }
    }

    // ------------------------------------------------------------------ build
    private FlipLabel L(Control parent, string text, float size, bool semi, FlipTone tone)
    {
        FlipLabel l = new FlipLabel();
        l.Text = text; l.Font = FlipFonts.Get(size, semi); l.SetTone(tone);
        parent.Controls.Add(l);
        return l;
    }

    private FlipCard Card(Control parent, string key, string title, string desc, string icon, FlipTone tone)
    {
        FlipCard c = new FlipCard();
        c.ActionKey = key; c.Title = title; c.Desc = desc; c.IconName = icon; c.ToneKey = tone; c.Backdrop = FlipRole.Bg;
        c.ActionClicked += delegate { Raise(key); };
        parent.Controls.Add(c);
        interactive.Add(c);
        return c;
    }

    private FlipButton Btn(Control parent, string text, FlipKind kind, string icon, FlipRole backdrop)
    {
        FlipButton b = new FlipButton();
        b.Text = text; b.Kind = kind; b.IconName = icon; b.Backdrop = backdrop;
        parent.Controls.Add(b);
        return b;
    }

    private void Raise(string key)
    {
        if (busy && key != "exit" && key != "refresh" && key != "cancel") { return; }
        RequestedAction = key;
        EventHandler h = ActionRequested;
        if (h != null) { h(this, EventArgs.Empty); }
    }

    private void BuildSide(Bitmap imgOne, Bitmap imgZero)
    {
        side = new FlipSurface(); side.Role = FlipRole.Side; Controls.Add(side);
        toggle = new FlipToggle(); toggle.ImgOne = imgOne; toggle.ImgZero = imgZero;
        toggle.Toggled += delegate { SetMode(toggle.IsZero, true); };
        side.Controls.Add(toggle);
        lblBrand = L(side, "Flipper Emulator", 16f, true, FlipTone.Text);
        lblVersion = L(side, "VERSION " + version, 8.5f, true, FlipTone.AccentText);
        lblTag = L(side, "Unofficial community helper", 8.5f, false, FlipTone.Muted);

        statusCard = new FlipSurface(); statusCard.Role = FlipRole.Card; statusCard.Backdrop = FlipRole.Side; statusCard.Rounded = true; statusCard.Bordered = true; statusCard.Radius = 12;
        side.Controls.Add(statusCard);
        lblStatusDot = L(statusCard, "\u25CF", 15f, false, FlipTone.Faint); lblStatusDot.Font = new Font("Segoe UI Symbol", 14f, FontStyle.Regular, GraphicsUnit.Point);
        lblStatusTitle = L(statusCard, "STOPPED", 10.5f, true, FlipTone.Text);
        lblStatusDetail = L(statusCard, "Checking the current state...", 8.5f, false, FlipTone.Muted);
        lblLive = L(statusCard, "Updated automatically", 7.5f, false, FlipTone.Faint);

        lblSvcHead = L(side, "LOCAL SERVICES", 7.8f, true, FlipTone.Faint);
        lblSvc1 = L(side, "Flipper OS      port 8899", 8.5f, false, FlipTone.Muted);
        lblSvc2 = L(side, "File Manager    port 8898", 8.5f, false, FlipTone.Muted);
        lblSvc3 = L(side, "Everything stays on this PC.", 8f, false, FlipTone.Faint);
        lblFooter = L(side, "Unofficial community helper\nNot affiliated with Flipper Devices.", 7.8f, false, FlipTone.Faint);
    }

    private void BuildMain(Bitmap imgZero)
    {
        main = new FlipSurface(); main.Role = FlipRole.Bg; Controls.Add(main);
        lblTitle = L(main, "Actions", 20f, true, FlipTone.Text);
        lblSub = L(main, "", 9f, false, FlipTone.Muted);
        btnRefresh = Btn(main, "Refresh", FlipKind.Ghost, "", FlipRole.Bg); btnRefresh.Size = new Size(92, 34);
        btnRefresh.Click += delegate { Raise("refresh"); };
        btnExit = Btn(main, "Exit App", FlipKind.Ghost, "", FlipRole.Bg); btnExit.Size = new Size(96, 34);
        btnExit.Click += delegate { Raise("exit"); };

        pageHost = new FlipSurface(); pageHost.Role = FlipRole.Bg; pageHost.AutoScroll = true; main.Controls.Add(pageHost);
        pageOne = new FlipSurface(); pageOne.Role = FlipRole.Bg; pageHost.Controls.Add(pageOne);
        pageZero = new FlipSurface(); pageZero.Role = FlipRole.Bg; pageHost.Controls.Add(pageZero);

        // ---- One page
        gStart = L(pageOne, "START", 7.8f, true, FlipTone.Faint);
        gManage = L(pageOne, "MANAGE", 7.8f, true, FlipTone.Faint);
        gMaint = L(pageOne, "MAINTENANCE", 7.8f, true, FlipTone.Faint);
        cardReal = Card(pageOne, "real", "Real Flipper OS", "Boots the experimental operating system in QEMU.", "os", FlipTone.Accent);
        cardReal.Featured = true; cardReal.OptionText = "Open File Manager too"; cardReal.OptionChecked = true;
        cardPreview = Card(pageOne, "preview", "FlipCTL Preview", "Fast, stable browser preview. No QEMU needed.", "preview", FlipTone.Accent);
        cardPower = Card(pageOne, "powermeter", "Power Meter Demo", "Opens the online Power Meter demo in your browser.", "bolt", FlipTone.Success);
        cardStop = Card(pageOne, "stop", "Stop Everything", "Stops the preview, the hidden browser and QEMU.", "stop", FlipTone.Warn);
        cardLog = Card(pageOne, "log", "Show Server Log", "Shows the latest preview server messages here.", "log", FlipTone.Muted);
        cardBackup = Card(pageOne, "backup", "Open PC File Backup", "Opens the folder with your File Manager backup.", "folder", FlipTone.Muted);
        cardReset = Card(pageOne, "reset", "Reset Flipper OS", "Deletes the OS image and the file backup. Fresh start.", "reset", FlipTone.Danger);
        cardReinstall = Card(pageOne, "reinstall", "Reinstall", "Removes everything, downloads it fresh, restores files.", "reinstall", FlipTone.Warn);
        cardWipe = Card(pageOne, "wipe", "Uninstall Everything", "Removes every trace from this PC and frees the disk space.", "trash", FlipTone.Danger);

        // ---- Zero page
        hero = new FlipSurface(); hero.Role = FlipRole.Card; hero.Backdrop = FlipRole.Bg; hero.Rounded = true; hero.Bordered = true; hero.Radius = 14;
        pageZero.Controls.Add(hero);
        zPic = new FlipPicture(); zPic.Img = imgZero; hero.Controls.Add(zPic);
        zHeroTitle = L(hero, "Flipper Zero Emulator", 16f, true, FlipTone.Text);
        zHeroDesc = L(hero, "Runs the real Flipper Zero firmware on an emulated STM32WB55 chip (Renode, inside WSL).", 9f, false, FlipTone.Muted);
        zBadge = new FlipBadge(); zBadge.Caption = "Checking..."; zBadge.ToneKey = FlipTone.Faint; zBadge.Backdrop = FlipRole.Card; hero.Controls.Add(zBadge);
        zInstall = Btn(hero, "Install Emulator", FlipKind.Primary, "download", FlipRole.Card);
        zInstall.Click += delegate { Raise(zInstalled ? "zero-reinstall" : "zero-install"); };
        interactive.Add(zInstall);

        launcher = new FlipSurface(); launcher.Role = FlipRole.Card; launcher.Backdrop = FlipRole.Bg; launcher.Rounded = true; launcher.Bordered = true; launcher.Radius = 14;
        pageZero.Controls.Add(launcher);
        zLaunchHead = L(launcher, "LAUNCHER", 7.8f, true, FlipTone.Faint);
        zFwLabel = L(launcher, "Firmware", 9f, true, FlipTone.Muted);
        segFirmware = new FlipSegment(); segFirmware.Items = new string[] { "Official", "Momentum", "Custom file" }; launcher.Controls.Add(segFirmware);
        segFirmware.SelectedChanged += delegate { UpdateZeroLayoutState(); EventHandler h = FirmwareChanged; if (h != null) { h(this, EventArgs.Empty); } };
        interactive.Add(segFirmware);
        zBrowse = Btn(launcher, "Browse...", FlipKind.Secondary, "", FlipRole.Card); zBrowse.FontSize = 9f;
        zBrowse.Click += delegate { Raise("zero-browse"); };
        interactive.Add(zBrowse);
        zCustomName = L(launcher, "", 8.75f, false, FlipTone.Muted);
        zStart = Btn(launcher, "Start", FlipKind.Primary, "play", FlipRole.Card); zStart.FontSize = 12f;
        zStart.Click += delegate { Raise("zero-start"); };
        interactive.Add(zStart);
        zDisplay = Btn(launcher, "Open Display", FlipKind.Secondary, "display", FlipRole.Card);
        zDisplay.Click += delegate { Raise("zero-show"); };
        interactive.Add(zDisplay);
        zHint = L(launcher, "In the display window:  arrows / WASD = D-pad   \u00B7   Enter / Space = OK   \u00B7   Backspace / Esc = Back   \u00B7   Q = close", 8.5f, false, FlipTone.Faint);

        zMaint = L(pageZero, "MAINTENANCE", 7.8f, true, FlipTone.Faint);
        zReset = Card(pageZero, "zero-reset", "Reset Flash", "Restores the bundled stock firmware in the emulated flash.", "reset", FlipTone.Warn);
        zWipe = Card(pageZero, "wipe", "Uninstall Everything", "Removes every trace from this PC and frees the disk space.", "trash", FlipTone.Danger);

        // ---- activity
        activity = new FlipSurface(); activity.Role = FlipRole.Card; activity.Backdrop = FlipRole.Bg; activity.Rounded = true; activity.Bordered = true; activity.Radius = 12;
        main.Controls.Add(activity);
        lblActivity = L(activity, "ACTIVITY", 7.8f, true, FlipTone.Faint);
        lblActState = L(activity, "Ready", 8.5f, false, FlipTone.Faint); lblActState.TextAlign = ContentAlignment.MiddleRight;
        btnClear = Btn(activity, "Clear", FlipKind.Ghost, "", FlipRole.Card); btnClear.FontSize = 8.5f; btnClear.Size = new Size(58, 24);
        btnClear.Click += delegate { LogBox.Clear(); };
        btnCancel = Btn(activity, "Cancel", FlipKind.Danger, "", FlipRole.Card); btnCancel.FontSize = 8.5f; btnCancel.Size = new Size(66, 24); btnCancel.Visible = false;
        btnCancel.Click += delegate { Raise("cancel"); };
        logWrap = new FlipSurface(); logWrap.Role = FlipRole.Log; logWrap.Backdrop = FlipRole.Card; logWrap.Rounded = true; logWrap.Radius = 8;
        activity.Controls.Add(logWrap);
        LogBox = new TextBox();
        LogBox.Multiline = true; LogBox.ReadOnly = true; LogBox.BorderStyle = BorderStyle.None; LogBox.ScrollBars = ScrollBars.Vertical; LogBox.WordWrap = true;
        LogBox.Font = FlipFonts.Mono(8.5f); LogBox.BackColor = FlipTheme.Cur.LogBg; LogBox.ForeColor = FlipTheme.Cur.LogText;
        logWrap.Controls.Add(LogBox);
        Progress = new FlipProgress(); Progress.Visible = false; activity.Controls.Add(Progress);
    }

    // ----------------------------------------------------------------- layout
    private void LayoutAll()
    {
        int W = ClientSize.Width, H = ClientSize.Height;
        if (side == null || W < 100) { return; }
        SuspendLayout();
        side.SetBounds(0, 0, SideW, H);
        main.SetBounds(SideW, 0, W - SideW, H);

        // sidebar
        int sx = 24, sw = SideW - 48;
        toggle.SetBounds(sx, 24, sw, 72);
        lblBrand.SetBounds(sx, 112, sw, 28);
        lblVersion.SetBounds(sx, 142, sw, 18);
        lblTag.SetBounds(sx, 162, sw, 18);
        statusCard.SetBounds(sx, 200, sw, 122);
        lblStatusDot.SetBounds(12, 10, 24, 26);
        lblStatusTitle.SetBounds(40, 12, sw - 52, 22);
        lblStatusDetail.SetBounds(40, 38, sw - 52, 62);
        lblLive.SetBounds(14, 100, sw - 28, 16);
        lblSvcHead.SetBounds(sx, 342, sw, 16);
        lblSvc1.SetBounds(sx, 364, sw, 18);
        lblSvc2.SetBounds(sx, 384, sw, 18);
        lblSvc3.SetBounds(sx, 408, sw, 18);
        lblFooter.SetBounds(sx, H - 58, sw, 36);

        // main chrome
        int mw = main.Width;
        int px = 28, pw = mw - 2 * px;
        lblTitle.SetBounds(px, 20, pw - 210, 36);
        lblSub.SetBounds(px, 58, pw - 210, 22);
        btnExit.SetBounds(mw - px - 96, 26, 96, 34);
        btnRefresh.SetBounds(mw - px - 96 - 10 - 92, 26, 92, 34);

        int actH = 150;
        int actY = H - actH - 20;
        activity.SetBounds(px, actY, pw, actH);
        int ax = 14;
        lblActivity.SetBounds(ax, 10, 120, 24);
        btnCancel.SetBounds(activity.Width - ax - 66, 10, 66, 24);
        btnClear.SetBounds(activity.Width - ax - 66 - (btnCancel.Visible ? 8 : 0) - 58 - (btnCancel.Visible ? 0 : 0), 10, 58, 24);
        if (!btnCancel.Visible) { btnClear.SetBounds(activity.Width - ax - 58, 10, 58, 24); }
        lblActState.SetBounds(160, 10, btnClear.Left - 160 - 10, 24);
        logWrap.SetBounds(ax, 40, activity.Width - 2 * ax, actH - 40 - 24);
        LogBox.SetBounds(8, 6, logWrap.Width - 16, logWrap.Height - 12);
        Progress.SetBounds(ax, actH - 18, activity.Width - 2 * ax, 8);

        int top = 92;
        int hostH = actY - top - 14;
        pageHost.SetBounds(px - 4, top, pw + 8, hostH);
        LayoutOne(pageHost.ClientSize.Width, hostH);
        LayoutZero(pageHost.ClientSize.Width, hostH);
        UpdateScroll();
        ResumeLayout();
    }

    private int NeedOne = 404;
    private int NeedZero = 440;

    private void LayoutOne(int hostW, int hostH)
    {
        bool scroll = hostH < NeedOne;
        int hh = Math.Max(hostH, NeedOne);
        int ox = 4; int w = hostW - 8 - (scroll ? 20 : 0);
        pageOne.SetBounds(0, 0, hostW, hh);
        int gap = 14;
        int cw = (w - 2 * gap) / 3;
        int labelH = 20;
        int free = hh - (2 + 3 * (labelH + 2) + 2 * 12 + 4);
        int h1 = (int)(free * 0.38f); if (h1 < 112) { h1 = 112; } if (h1 > 140) { h1 = 140; }
        int h23 = (free - h1) / 2; if (h23 < 90) { h23 = 90; } if (h23 > 112) { h23 = 112; }
        int y = 2;
        gStart.SetBounds(ox + 2, y, 200, labelH); y += labelH + 2;
        cardReal.SetBounds(ox, y, cw, h1);
        cardPreview.SetBounds(ox + cw + gap, y, cw, h1);
        cardPower.SetBounds(ox + 2 * (cw + gap), y, w - 2 * (cw + gap), h1);
        y += h1 + 12;
        gManage.SetBounds(ox + 2, y, 200, labelH); y += labelH + 2;
        cardStop.SetBounds(ox, y, cw, h23);
        cardLog.SetBounds(ox + cw + gap, y, cw, h23);
        cardBackup.SetBounds(ox + 2 * (cw + gap), y, w - 2 * (cw + gap), h23);
        y += h23 + 12;
        gMaint.SetBounds(ox + 2, y, 200, labelH); y += labelH + 2;
        cardReset.SetBounds(ox, y, cw, h23);
        cardReinstall.SetBounds(ox + cw + gap, y, cw, h23);
        cardWipe.SetBounds(ox + 2 * (cw + gap), y, w - 2 * (cw + gap), h23);
        y += h23 + 4;
        pageOne.Height = Math.Max(hh, y);
    }

    private void LayoutZero(int hostW, int hostH)
    {
        bool scroll = hostH < NeedZero;
        int hh = Math.Max(hostH, NeedZero);
        int ox = 4; int w = hostW - 8 - (scroll ? 20 : 0);
        pageZero.SetBounds(0, 0, hostW, hh);
        int y = 2;
        int heroH = 120;
        hero.SetBounds(ox, y, w, heroH);
        int picW = 180;
        zPic.SetBounds(18, 12, picW, heroH - 24);
        int tx = 18 + picW + 22;
        zHeroTitle.SetBounds(tx, 16, w - tx - 220, 30);
        zBadge.Width = zBadge.PreferredWidth(); zBadge.Location = new Point(tx, 50);
        zHeroDesc.SetBounds(tx, 80, w - tx - 220, 36);
        zInstall.SetBounds(w - 18 - 190, (heroH - 42) / 2, 190, 42);
        y += heroH + 14;
        int launchH = 176;
        launcher.SetBounds(ox, y, w, launchH);
        zLaunchHead.SetBounds(20, 12, 200, 16);
        zFwLabel.SetBounds(20, 36, 80, 38);
        zFwLabel.TextAlign = ContentAlignment.MiddleLeft;
        int segW = Math.Max(240, Math.Min(400, w - 20 - 90 - 230));
        segFirmware.SetBounds(100, 36, segW, 38);
        zBrowse.SetBounds(100 + segW + 12, 38, 96, 34);
        zCustomName.SetBounds(100 + segW + 12 + 96 + 10, 36, Math.Max(40, w - (100 + segW + 12 + 96 + 10) - 20), 38);
        zCustomName.TextAlign = ContentAlignment.MiddleLeft;
        zStart.SetBounds(20, 88, 230, 50);
        zDisplay.SetBounds(20 + 230 + 12, 88, 190, 50);
        zHint.SetBounds(20, 146, w - 40, 22);
        y += launchH + 14;
        zMaint.SetBounds(ox + 2, y, 200, 20); y += 22;
        int gap = 14; int cw = (w - gap) / 2;
        zReset.SetBounds(ox, y, cw, 92);
        zWipe.SetBounds(ox + cw + gap, y, w - cw - gap, 92);
        y += 96;
        pageZero.Height = Math.Max(hh, y);
        UpdateZeroLayoutState();
    }

    private void UpdateScroll()
    {
        int need = zeroMode ? NeedZero : NeedOne;
        bool scroll = pageHost.Height < need;
        pageHost.AutoScroll = scroll;
        if (scroll) { pageHost.AutoScrollMinSize = new Size(0, need); }
    }

    // ------------------------------------------------------------- behaviour
    private void SetMode(bool zero, bool animate)
    {
        zeroMode = zero;
        if (toggle.IsZero != zero) { toggle.SetZero(zero, animate, false); }
        pageOne.Visible = !zero;
        pageZero.Visible = zero;
        pageHost.AutoScrollPosition = new Point(0, 0);
        UpdateScroll();
        if (zero)
        {
            lblTitle.Text = "Launcher";
            lblSub.Text = "Choose a firmware and press Start. The real Flipper Zero firmware runs on your PC.";
            lblSvcHead.Text = "EMULATOR";
            lblSvc1.Text = "Engine         Renode (WSL)";
            lblSvc2.Text = "Firmware      " + FirmwareName();
            lblSvc3.Text = "Everything stays on this PC.";
        }
        else
        {
            lblTitle.Text = "Actions";
            lblSub.Text = "Choose what you want to do. Long operations keep running and report in the activity log.";
            lblSvcHead.Text = "LOCAL SERVICES";
            lblSvc1.Text = "Flipper OS      port 8899";
            lblSvc2.Text = "File Manager    port 8898";
            lblSvc3.Text = "Everything stays on this PC.";
        }
        lblTag.Text = zero ? "Flipper Zero emulator" : "Unofficial community helper";
        FlipTheme.AnimateTo(zero);
        if (IsHandleCreated) { FlipNative.TitleBar(Handle, !zero); }
        UpdateZeroLayoutState();
        EventHandler h = ModeChanged;
        if (h != null) { h(this, EventArgs.Empty); }
    }

    private string FirmwareName()
    {
        if (segFirmware == null) { return officialLabel; }
        if (segFirmware.SelectedIndex == 1) { return "Momentum"; }
        if (segFirmware.SelectedIndex == 2) { return customName.Length > 0 ? customName : "Custom file"; }
        return officialLabel;
    }

    private void UpdateZeroLayoutState()
    {
        if (zBrowse == null) { return; }
        bool custom = segFirmware.SelectedIndex == 2;
        zBrowse.Visible = custom;
        zCustomName.Visible = custom;
        zCustomName.Text = customName.Length > 0 ? customName : "No file chosen yet";
        if (zeroMode) { lblSvc2.Text = "Firmware      " + FirmwareName(); }
    }

    // --- calls from PowerShell
    public void SetOfficialLabel(string label) { officialLabel = label; UpdateZeroLayoutState(); }
    public void SetCustomFirmware(string name) { customName = name == null ? "" : name; UpdateZeroLayoutState(); }

    public void SetStatus(string title, string detail, string tone)
    {
        lblStatusTitle.Text = title;
        lblStatusDetail.Text = detail;
        FlipTone t = FlipTone.Faint;
        try { t = (FlipTone)Enum.Parse(typeof(FlipTone), tone); } catch (Exception) { }
        lblStatusDot.SetTone(t);
    }

    public void SetServiceLines(string l1, string l2)
    {
        if (zeroMode) { return; }
        lblSvc1.Text = l1; lblSvc2.Text = l2;
    }

    public void SetZeroState(bool installed, bool running)
    {
        zInstalled = installed;
        zRunning = running;
        zInstall.Text = installed ? "Reinstall Emulator" : "Install Emulator";
        zInstall.IconName = installed ? "reinstall" : "download";
        zInstall.Kind = installed ? FlipKind.Secondary : FlipKind.Primary;
        zInstall.Invalidate();
        zBadge.Caption = running ? "Running" : (installed ? "Installed" : "Not installed");
        zBadge.ToneKey = running ? FlipTone.Success : (installed ? FlipTone.Success : FlipTone.Warn);
        zBadge.Width = zBadge.PreferredWidth();
        zBadge.Invalidate();
        zStart.Text = running ? "Stop" : "Start";
        zStart.IconName = running ? "stop" : "play";
        zStart.Kind = running ? FlipKind.Stop : FlipKind.Primary;
        zStart.Invalidate();
        ApplyEnabled();
    }

    public void SetBusy(bool b)
    {
        busy = b;
        btnCancel.Visible = b;
        Progress.Visible = b;
        ApplyEnabled();
        LayoutAll();
    }

    private void ApplyEnabled()
    {
        foreach (Control c in interactive) { c.Enabled = !busy; }
        if (!busy)
        {
            zStart.Enabled = zInstalled;
            zDisplay.Enabled = zInstalled && zRunning;
            zReset.Enabled = zInstalled && !zRunning;
            segFirmware.Enabled = !zRunning;
            zBrowse.Enabled = !zRunning;
        }
        else
        {
            zStart.Enabled = false; zDisplay.Enabled = false;
        }
    }

    public void SetActivity(string text, string tone)
    {
        lblActState.Text = text;
        FlipTone t = FlipTone.Faint;
        try { t = (FlipTone)Enum.Parse(typeof(FlipTone), tone); } catch (Exception) { }
        lblActState.SetTone(t);
    }

    public void AppendLog(string text)
    {
        LogBox.AppendText(text);
        LogBox.SelectionStart = LogBox.TextLength;
        LogBox.ScrollToCaret();
    }
}
'@

function Initialize-UiTypes {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if ('FlipperMainForm' -as [type]) { return }
    Add-Type -TypeDefinition $script:UiSource -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -ErrorAction Stop
}

function Test-UiTcpPort {
    param([int]$Port, [int]$Timeout = 250)
    if ($Port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($Timeout)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

function Get-UiSnapshot {
    $real = $false
    if (Test-Path $QemuPidFile) {
        $qp = [string](Get-Content -LiteralPath $QemuPidFile -ErrorAction SilentlyContinue)
        if ($qp -match '^\d+$' -and (Get-Process -Id ([int]$qp) -ErrorAction SilentlyContinue)) { $real = $true }
    }
    if (-not $real) {
        $qemu = Get-Process -Name 'qemu-system-aarch64' -ErrorAction SilentlyContinue
        if ($qemu) {
            $q = Get-CimInstance Win32_Process -Filter "Name='qemu-system-aarch64.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and $_.CommandLine -like '*flipper-os.img*' } |
                Select-Object -First 1
            if ($q) { $real = $true }
        }
    }
    $preview = $false
    if (-not $real) {
        if (Test-Path $ServerPidFile) {
            $sp = [string](Get-Content -LiteralPath $ServerPidFile -ErrorAction SilentlyContinue)
            if ($sp -match '^\d+$' -and (Get-Process -Id ([int]$sp) -ErrorAction SilentlyContinue)) { $preview = $true }
        }
        if (-not $preview) { $preview = Test-UiTcpPort -Port $Port -Timeout 200 }
    }
    $appPort = Read-AppPort
    $shelfPort = Read-ShelfPort
    if ($preview -and -not $real) { $appPort = $Port }
    $shelf = $false
    if ($real) { $shelf = Test-UiTcpPort -Port $shelfPort -Timeout 250 }
    return [pscustomobject]@{
        Real      = $real
        Preview   = $preview
        Shelf     = $shelf
        AppPort   = $appPort
        ShelfPort = $shelfPort
    }
}

function Set-UiStatus {
    param([string]$State, [string]$Detail, [string]$Tone)
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    $script:UiForm.SetStatus($State, $Detail, $Tone)
}

function Set-UiActivity {
    param([string]$Text, [string]$Tone)
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    $script:UiForm.SetActivity($Text, $Tone)
}

function Apply-UiOneStatus {
    $c = $script:UiOneCache
    if ($c) {
        $script:UiForm.SetServiceLines($c.Line1, $c.Line2)
        Set-UiStatus $c.State $c.Detail $c.Tone
    } else {
        Set-UiStatus 'STOPPED' 'Checking the current state...' 'Faint'
    }
}

function Refresh-UiStatus {
    if (-not $script:UiForm -or $script:UiForm.IsDisposed -or $script:UiBusy) { return }
    if ($script:UiMode -eq 'zero') { Refresh-ZeroUiStatus; return }
    $snapshot = Get-UiSnapshot
    $state = 'STOPPED'; $detail = 'No services are running. Choose an action to begin.'; $tone = 'Faint'
    if ($snapshot.Real) {
        $state = 'REAL OS RUNNING'
        if ($snapshot.Shelf) {
            $detail = 'The real Flipper OS and the File Manager are running.'; $tone = 'Success'
        } else {
            $detail = 'The real Flipper OS is running. The File Manager is starting or unavailable.'; $tone = 'Accent'
        }
    } elseif ($snapshot.Preview) {
        $state = 'PREVIEW RUNNING'; $detail = 'The FlipCTL preview is running in the background.'; $tone = 'Success'
    }
    $script:UiOneCache = @{
        Line1  = "Flipper OS      port $($snapshot.AppPort)"
        Line2  = "File Manager    port $($snapshot.ShelfPort)"
        State  = $state
        Detail = $detail
        Tone   = $tone
    }
    if ($script:UiMode -eq 'one') { Apply-UiOneStatus }
}

function Set-UiBusyAppearance {
    param([bool]$Busy)
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    $script:UiForm.SetBusy($Busy)
    $script:UiForm.Progress.Marquee = $Busy
    if ($Busy) { Set-UiActivity 'Working' 'Warn' } else { Set-UiActivity 'Ready' 'Faint' }
}

function Initialize-UiWorkspace {
    $temp = $env:TEMP
    if (-not $temp) { $temp = Join-Path $env:LOCALAPPDATA 'Temp' }
    $script:UiWork = Join-Path $temp ('FlipperOneDemo-ui-' + $PID)
    Remove-Item -LiteralPath $script:UiWork -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $script:UiWork | Out-Null
    $source = $script:SelfSource
    if (-not $source -or -not (Test-Path -LiteralPath $source)) { $source = $env:FLIP_BAT }
    if (-not $source -or -not (Test-Path -LiteralPath $source)) { throw 'The helper file could not be found.' }
    $script:UiBat = Join-Path $script:UiWork ('FlipperEmulator ' + $Version + '.bat')
    Copy-Item -LiteralPath $source -Destination $script:UiBat -Force
}

function Add-UiLogMessage([string]$Message) {
    if (-not $script:UiLogBox) { return }
    $stamp = Get-Date -Format 'HH:mm:ss'
    $script:UiLogBox.AppendText("[$stamp] $Message`r`n")
    $script:UiLogBox.SelectionStart = $script:UiLogBox.TextLength
    $script:UiLogBox.ScrollToCaret()
}

function Update-UiLog {
    if (-not $script:UiLogPath -or -not (Test-Path -LiteralPath $script:UiLogPath)) { return }
    try {
        $fs = New-Object System.IO.FileStream($script:UiLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
        } finally {
            $fs.Dispose()
        }
    } catch {
        return
    }
    if ($text.Length -le $script:UiLogChars) { return }
    $chunk = $text.Substring($script:UiLogChars)
    $script:UiLogChars = $text.Length
    $chunk = $chunk -replace "`r`n", "`n"
    $chunk = $chunk -replace "`r", "`n"
    $chunk = $chunk -replace "`n", "`r`n"
    $chunk = $chunk -replace "`0", ''
    $escape = [string][char]27
    if ($escape) { $chunk = [regex]::Replace($chunk, [regex]::Escape($escape) + '\[[0-9;?]*[ -/]*[@-~]', '') }
    if ($chunk.Length -eq 0) { return }
    $script:UiLogText += $chunk
    $script:UiLogBox.AppendText($chunk)
    $script:UiLogBox.SelectionStart = $script:UiLogBox.TextLength
    $script:UiLogBox.ScrollToCaret()
}

function Open-UiBackup {
    New-Item -ItemType Directory -Force -Path $FilesMirror | Out-Null
    Start-Process explorer.exe $FilesMirror
    Add-UiLogMessage "Opened the PC file backup: $FilesMirror"
}

function Confirm-UiAction {
    param(
        [string]$Title,
        [string]$Heading,
        [string]$Body,
        [string]$Phrase,
        [string]$ConfirmText,
        [string]$Tone,
        [bool]$CaseSensitive
    )
    return [FlipConfirmDialog]::Confirm($script:UiForm, $Title, $Heading, $Body, $Phrase, $ConfirmText, [FlipTone]$Tone, $CaseSensitive)
}

function Show-UiMessage {
    param(
        [string]$Text,
        [string]$Title = 'Flipper Emulator',
        [string]$Kind = 'Information'
    )
    $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($Kind -eq 'Warning') { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
    if ($Kind -eq 'Error') { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
    [void][System.Windows.Forms.MessageBox]::Show($script:UiForm, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

function Select-UiCustomFirmware {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose a Flipper Zero firmware'
    $dlg.Filter = 'Firmware files (*.tgz;*.bin;*.dfu)|*.tgz;*.bin;*.dfu|All files (*.*)|*.*'
    $chosen = $false
    try {
        if ($dlg.ShowDialog($script:UiForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:ZeroCustomFirmware = $dlg.FileName
            $script:UiForm.SetCustomFirmware([IO.Path]::GetFileName($dlg.FileName))
            Add-UiLogMessage ('Custom firmware: ' + $dlg.FileName)
            $chosen = $true
        }
    } finally {
        $dlg.Dispose()
    }
    return $chosen
}

function Cancel-UiConfirm {
    param([string]$What)
    Set-UiActivity 'Cancelled' 'Faint'
    Add-UiLogMessage "$What cancelled. Nothing was changed."
}

# Entry point for every click in the window.
function Invoke-UiAction {
    param([string]$Key)
    switch ($Key) {
        'exit' { $script:UiForm.Close(); return }
        'cancel' { Stop-UiAction; return }
        'backup' { if (-not $script:UiBusy) { Open-UiBackup }; return }
        'powermeter' {
            Start-Process 'https://dev.repetren.com/power_meter_demo/'
            Add-UiLogMessage 'Opened the Power Meter demo in your browser.'
            return
        }
        'refresh' {
            if ($script:UiBusy) { return }
            if ($script:UiMode -eq 'zero') { $null = Test-ZeroInstalled -Refresh }
            Refresh-UiStatus
            $script:UiLastStatus = Get-Date
            Add-UiLogMessage 'Status refreshed.'
            return
        }
        'zero-browse' { $null = Select-UiCustomFirmware; return }
        'zero-start' {
            if ($script:UiBusy) { return }
            if (Test-ZeroRunning) { Start-UiAction 'zero-stop'; return }
            if ($script:ZeroBranch -eq 'custom') {
                if (-not $script:ZeroCustomFirmware -or -not (Test-Path -LiteralPath $script:ZeroCustomFirmware)) {
                    if (-not (Select-UiCustomFirmware)) { return }
                }
            }
            Start-UiAction 'zero-run'
            return
        }
        default { Start-UiAction $Key; return }
    }
}

function Start-UiAction {
    param([string]$Action)
    if ($script:UiBusy) { return }

    # The Real Flipper OS card can open the File Manager together with the OS.
    if ($Action -eq 'real' -and $script:UiForm.OpenFileManager) { $Action = 'files' }

    $title = switch ($Action) {
        'preview'        { 'Starting the FlipCTL preview' }
        'real'           { 'Starting the real Flipper OS' }
        'files'          { 'Starting Flipper OS and File Manager' }
        'stop'           { 'Stopping everything' }
        'log'            { 'Loading the server log' }
        'reinstall'      { 'Reinstalling Flipper One' }
        'reset'          { 'Resetting the Flipper OS' }
        'wipe'           { 'Removing everything from this PC' }
        'zero-install'   { 'Installing the Flipper Zero emulator' }
        'zero-reinstall' { 'Reinstalling the Flipper Zero emulator' }
        'zero-run'       { 'Starting the Flipper Zero emulator' }
        'zero-stop'      { 'Stopping the Flipper Zero emulator' }
        'zero-show'      { 'Opening the Flipper Zero display' }
        'zero-reset'     { 'Resetting the Flipper Zero flash' }
        default          { 'Working' }
    }

    if ($Action -eq 'wipe') {
        $body = "This permanently removes everything Flipper Emulator has put on this PC:" +
                "`n  - the private Linux environment (FlipperOne) with the Flipper Zero emulator" +
                "`n  - the portable QEMU and the Flipper OS image" +
                "`n  - all downloaded firmwares and installers" +
                "`n  - your File Manager files and the PC file backup" +
                "`n  - Start menu shortcuts and temporary files" +
                "`n`nAll of this disk space is free again afterwards. Your own files, this program file and Windows' WSL feature are not touched."
        $ok = Confirm-UiAction -Title 'Uninstall Everything' -Heading 'Remove everything from this PC?' `
            -Body $body -Phrase 'DELETE' -ConfirmText 'Remove everything' -Tone 'Danger' -CaseSensitive $true
        if (-not $ok) { Cancel-UiConfirm 'Removal'; return }
    }
    if ($Action -eq 'reinstall') {
        $body = "This removes the Flipper One setup and its downloads, downloads a fresh copy, and restores the PC file backup." +
                "`n`nThis needs an internet connection and several GB of free space. It can take several minutes."
        if (Test-ZeroInstalled) {
            $body += "`n`nThe Flipper Zero emulator lives in the same Linux environment, so it is removed as well and has to be installed again."
        }
        $ok = Confirm-UiAction -Title 'Reinstall Flipper One' -Heading 'Download a fresh setup?' `
            -Body $body -Phrase 'YES' -ConfirmText 'Reinstall' -Tone 'Warn' -CaseSensitive $false
        if (-not $ok) { Cancel-UiConfirm 'Reinstall'; return }
    }
    if ($Action -eq 'reset') {
        $body = "This deletes the real Flipper OS image with all apps, settings and files inside it." +
                "`nIt also deletes the PC file backup in %LOCALAPPDATA%\FlipperOneDemoFiles." +
                "`n`nThe Windows helper, its downloads and the FlipCTL preview are kept."
        $ok = Confirm-UiAction -Title 'Reset Flipper OS' -Heading 'Factory reset the Flipper OS?' `
            -Body $body -Phrase 'RESET' -ConfirmText 'Reset Flipper OS' -Tone 'Danger' -CaseSensitive $true
        if (-not $ok) { Cancel-UiConfirm 'Factory reset'; return }
    }
    if ($Action -eq 'zero-reinstall') {
        $body = "This deletes the installed Flipper Zero emulator (including its emulated SD card and flash) and downloaded firmwares, then installs it again from scratch." +
                "`n`nThis needs an internet connection and can take 15-30 minutes."
        $ok = Confirm-UiAction -Title 'Reinstall Flipper Zero emulator' -Heading 'Install the emulator again?' `
            -Body $body -Phrase 'YES' -ConfirmText 'Reinstall' -Tone 'Warn' -CaseSensitive $false
        if (-not $ok) { Cancel-UiConfirm 'Reinstall'; return }
    }

    if (-not (Test-Path -LiteralPath $script:UiBat)) {
        Show-UiMessage 'The helper copy for this window is missing. Close the app and start it again.' 'Flipper Emulator' 'Error'
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $logPath = Join-Path $script:UiWork ("run-$stamp-$Action-$suffix.log")
    $wrapper = Join-Path $script:UiWork ("run-$stamp-$Action-$suffix.cmd")
    $content = "@echo off`r`n" +
               "chcp 65001 >nul`r`n" +
               "set `"FLIP_UI=1`"`r`n" +
               "call `"$($script:UiBat)`" ui-$Action > `"$logPath`" 2>&1`r`n" +
               "exit /b %errorlevel%`r`n"
    if ($Action -eq 'zero-run') {
        $sel = @{ branch = [string]$script:ZeroBranch; custom = [string]$script:ZeroCustomFirmware }
        try {
            $json = $sel | ConvertTo-Json -Compress
            New-Item -ItemType Directory -Force -Path $Root | Out-Null
            [IO.File]::WriteAllText((Join-Path $Root 'zero-selection.json'), $json, (New-Object Text.UTF8Encoding($false)))
        } catch { }
    }
    [IO.File]::WriteAllText($wrapper, $content, (New-Object System.Text.UTF8Encoding($false)))

    $script:UiBusy = $true
    $script:UiAction = $Action
    $script:UiActionTitle = $title
    $script:UiLogPath = $logPath
    $script:UiLogChars = 0
    $script:UiLogText = ''
    $script:UiLogBox.Clear()
    $script:UiLogBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $title`r`n")
    Set-UiBusyAppearance $true
    Set-UiStatus 'WORKING' $title 'Warn'
    Set-UiActivity $title 'Warn'

    try {
        $script:UiProcess = Start-Process -FilePath $wrapper -WorkingDirectory $script:UiWork -WindowStyle Hidden -PassThru
    } catch {
        $script:UiBusy = $false
        $script:UiProcess = $null
        $script:UiLogPath = $null
        Set-UiBusyAppearance $false
        Refresh-UiStatus
        Show-UiMessage ("The action could not be started.`n`n" + $_.Exception.Message) 'Flipper Emulator' 'Error'
    }
}

function Complete-UiAction {
    if (-not $script:UiProcess) { return }
    Update-UiLog
    $code = 0
    try { $code = $script:UiProcess.ExitCode } catch { }
    try { $script:UiProcess.Dispose() } catch { }
    $script:UiProcess = $null
    $action = $script:UiAction
    $script:UiBusy = $false
    $script:UiLogPath = $null
    $script:UiLogChars = 0
    Set-UiBusyAppearance $false
    if ($action -like 'zero-*' -or $action -eq 'wipe' -or $action -eq 'reinstall') { $script:ZeroInstalled = $null }
    if ($action -eq 'wipe' -or $action -eq 'reinstall') { $script:UiOneCache = $null }
    Refresh-UiStatus

    $needsRestart = $script:UiLogText -match 'UI-EVENT:RESTART_REQUIRED'
    $hasWarning = $script:UiLogText -match '(?m)^\s*(!!|XX)\s'

    if ($needsRestart) {
        Show-UiMessage "Windows needs one restart to finish enabling WSL.`n`nAfter you sign in again, the helper continues automatically. If it does not, start the app again." 'Restart Windows' 'Information'
        $script:UiForm.Close()
        return
    }
    if ($code -ne 0) {
        Set-UiActivity 'Needs attention' 'Danger'
        Show-UiMessage "The action did not finish (exit code $code).`n`nSee the activity log for details." 'Flipper Emulator' 'Error'
    } elseif ($action -eq 'wipe') {
        Set-UiActivity 'Everything removed' 'Muted'
        Show-UiMessage "Everything Flipper Emulator installed has been removed from this PC and the disk space is free again.`n`nThis window stays open. Starting something again simply installs it again." 'Removal finished' 'Information'
    } elseif ($action -eq 'reset') {
        Set-UiActivity 'Reset finished' 'Danger'
        Show-UiMessage "The Flipper OS has been reset to factory state.`n`nThe next start creates a fresh Flipper. Apps, settings and files inside it are gone." 'Factory reset finished' 'Information'
    } elseif ($action -eq 'zero-install' -or $action -eq 'zero-reinstall') {
        Set-UiActivity 'Emulator installed' 'Success'
        Show-UiMessage "The Flipper Zero emulator is installed.`n`nChoose a firmware and press Start." 'Flipper Zero' 'Information'
    } elseif ($action -eq 'zero-run') {
        Set-UiActivity 'Emulator running' 'Success'
    } elseif ($action -eq 'zero-stop') {
        Set-UiActivity 'Emulator stopped' 'Muted'
    } elseif ($action -eq 'zero-reset') {
        Set-UiActivity 'Flash reset' 'Muted'
    } elseif ($hasWarning) {
        Set-UiActivity 'Finished with warnings' 'Warn'
    } else {
        Set-UiActivity 'Finished' 'Success'
    }

    $script:UiAction = ''
    $script:UiActionTitle = ''
}

function Stop-UiAction {
    if (-not $script:UiBusy) { return }
    $action = $script:UiAction
    Add-UiLogMessage 'Cancelling the running action ...'
    if ($script:UiProcess) {
        try { & "$env:SystemRoot\System32\taskkill.exe" /PID $script:UiProcess.Id /T /F 2>&1 | Out-Null } catch { }
        try { $script:UiProcess.Dispose() } catch { }
        $script:UiProcess = $null
    }
    if ($action -like 'zero-*') {
        try {
            & wsl.exe -d FlipperOne -- bash -c "pkill -9 -f '[i]nstall-zero.sh' 2>/dev/null; pkill -9 -f '[a]pt-get' 2>/dev/null; pkill -9 -f '[g]it clone' 2>/dev/null; true" 2>&1 | Out-Null
        } catch { }
        if ($action -eq 'zero-install' -or $action -eq 'zero-reinstall') {
            & wsl.exe --terminate FlipperOne 2>&1 | Out-Null
            $script:ZeroInstalled = $null
        }
        if ($action -eq 'zero-run') {
            Stop-ZeroEmulator -Quiet
        }
    }
    $script:UiBusy = $false
    $script:UiAction = ''
    $script:UiActionTitle = ''
    $script:UiLogPath = $null
    $script:UiLogChars = 0
    Set-UiBusyAppearance $false
    Set-UiActivity 'Cancelled' 'Warn'
    Add-UiLogMessage 'Action cancelled.'
    Refresh-UiStatus
}

function Update-Ui {
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    if ($script:UiBusy -and $script:UiProcess) {
        Update-UiLog
        $exited = $false
        try { $exited = $script:UiProcess.HasExited } catch { $exited = $false }
        if ($exited) { Complete-UiAction }
    }
    if (-not $script:UiBusy) {
        # Never refresh in the middle of the colour fade: the checks can take a moment.
        if ([FlipTheme]::Animating) { return }
        if (((Get-Date) - $script:UiLastStatus).TotalSeconds -ge 5) {
            Refresh-UiStatus
            $script:UiLastStatus = Get-Date
        }
    }
}

# ---------------------------------------------------------------------------
# Flipper Zero emulator
# ---------------------------------------------------------------------------
$script:ZeroInstalled      = $null
$script:ZeroRunPidFile     = Join-Path $Root 'zero-run.pid'
$script:ZeroViewerPidFile  = Join-Path $Root 'zero-viewer.pid'
$script:ZeroFlag           = Join-Path $Root 'zero-installed.flag'

function Get-ZeroWslPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    $p = $Path -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)$') {
        return ('/mnt/' + $Matches[1].ToLower() + $Matches[2])
    }
    return $p
}

function Read-ZeroPid {
    param([string]$File)
    try {
        if (-not (Test-Path -LiteralPath $File)) { return 0 }
        $v = [string](Get-Content -LiteralPath $File -ErrorAction SilentlyContinue)
        if ($v -match '^\d+$') {
            $id = [int]$v
            if (Get-Process -Id $id -ErrorAction SilentlyContinue) { return $id }
        }
    } catch { }
    Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    return 0
}

function Test-ZeroRunning {
    return ((Read-ZeroPid $script:ZeroRunPidFile) -gt 0)
}

function Test-ZeroInstalled {
    param([switch]$Refresh)
    if (-not $Refresh -and $null -ne $script:ZeroInstalled) { return [bool]$script:ZeroInstalled }
    # Fast path: a marker written by the installer. It avoids starting the Linux
    # environment just to draw the window.
    if (-not $Refresh -and (Test-Path -LiteralPath $script:ZeroFlag)) {
        $script:ZeroInstalled = $true
        return $true
    }
    $installed = $false
    try {
        if (Test-Distro) {
            $check = & wsl.exe -d $Distro -- bash -c "test -x ~/flipper-zero-emulator/tools/renode/renode && test -f ~/flipper-zero-emulator/run.sh && echo YES || echo NO" 2>&1
            $installed = [bool](($check | Out-String) -match 'YES')
        }
    } catch {
        $installed = $false
    }
    $script:ZeroInstalled = $installed
    try {
        if ($installed) {
            New-Item -ItemType Directory -Force -Path $Root | Out-Null
            Set-Content -LiteralPath $script:ZeroFlag -Value ('installed=' + (Get-Date).ToString('u')) -Encoding ASCII
        } else {
            Remove-Item -LiteralPath $script:ZeroFlag -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    return $installed
}

function Refresh-ZeroUiStatus {
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    $installed = Test-ZeroInstalled
    $running = $false
    if ($installed) { $running = Test-ZeroRunning }
    $script:UiForm.SetZeroState($installed, $running)
    if ($script:UiBusy) { return }
    if (-not $installed) {
        Set-UiStatus 'NOT INSTALLED' 'The Flipper Zero emulator is not installed yet. Click Install Emulator.' 'Warn'
    } elseif ($running) {
        if ((Read-ZeroPid $script:ZeroViewerPidFile) -gt 0) {
            Set-UiStatus 'EMULATOR RUNNING' 'The Flipper Zero is running and its display window is open.' 'Success'
        } else {
            Set-UiStatus 'EMULATOR RUNNING' 'The Flipper Zero is running. Click Open Display to show its screen.' 'Success'
        }
    } else {
        Set-UiStatus 'READY' 'The emulator is installed. Choose a firmware and press Start.' 'Faint'
    }
}

function Write-ZeroHelperScripts {
    $viewerCode = @'
param(
    [string]$FbPath = '\\wsl.localhost\FlipperOne\tmp\flipper_fb.raw',
    [int]$Port = 1234,
    [string]$LogPath = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Background frame reader: the (slow) read of the framebuffer over the WSL share
# runs on its own thread so it can never delay keyboard/mouse handling.
if (-not ('ZeroFbReader' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading;

public class ZeroFbReader
{
    private readonly string _path;
    private Thread _thread;
    private volatile bool _stop;
    private readonly object _lock = new object();
    private byte[] _latest;
    private long _version;
    private long _returned;

    public ZeroFbReader(string path)
    {
        _path = path;
    }

    public void Start()
    {
        _thread = new Thread(Loop);
        _thread.IsBackground = true;
        _thread.Start();
    }

    public void Stop()
    {
        _stop = true;
    }

    private void Loop()
    {
        byte[] last = null;
        while (!_stop)
        {
            try
            {
                byte[] b = File.ReadAllBytes(_path);
                if (b.Length >= 8192)
                {
                    bool same = (last != null);
                    if (same)
                    {
                        for (int i = 0; i < 8192; i++)
                        {
                            if (b[i] != last[i]) { same = false; break; }
                        }
                    }
                    if (!same)
                    {
                        lock (_lock) { _latest = b; _version++; }
                        last = b;
                    }
                }
            }
            catch (Exception) { }
            Thread.Sleep(20);
        }
    }

    // Returns the newest frame converted to ARGB pixels, or null when nothing changed.
    public int[] GetPixelsIfNew()
    {
        byte[] src;
        lock (_lock)
        {
            if (_latest == null || _version == _returned) { return null; }
            src = _latest;
            _returned = _version;
        }
        int[] px = new int[8192];
        for (int i = 0; i < 8192; i++)
        {
            px[i] = (src[i] != 0) ? unchecked((int)0xFFFF8C00) : unchecked((int)0xFF000000);
        }
        return px;
    }
}
"@
}

if (-not $LogPath) { $LogPath = Join-Path $env:LOCALAPPDATA 'FlipperOneDemo\zero-viewer.log' }
function Write-Log([string]$msg) {
    try { Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) } catch { }
}
Write-Log "viewer start fb=$FbPath port=$Port"

$buttons = @{
    'Up'    = @('gpioPortB', 10, $true)
    'Down'  = @('gpioPortC', 6, $true)
    'Left'  = @('gpioPortB', 11, $true)
    'Right' = @('gpioPortB', 12, $true)
    'Ok'    = @('gpioPortH', 3, $false)
    'Back'  = @('gpioPortC', 13, $true)
}
$keyMap = @{
    'Up' = 'Up'; 'W' = 'Up'
    'Down' = 'Down'; 'S' = 'Down'
    'Left' = 'Left'; 'A' = 'Left'
    'Right' = 'Right'; 'D' = 'Right'
    'Return' = 'Ok'; 'Space' = 'Ok'; 'Enter' = 'Ok'
    'Back' = 'Back'; 'Escape' = 'Back'
}

$script:client = $null
$script:stream = $null
$script:writer = $null
$script:connected = $false
$script:lastConnect = [DateTime]::MinValue

function Connect-Monitor {
    if ($script:connected) { return }
    if (((Get-Date) - $script:lastConnect).TotalSeconds -lt 1) { return }
    $script:lastConnect = Get-Date
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $task = $c.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait(400)) { $c.Close(); throw 'connect timeout' }
        $script:client = $c
        $script:stream = $c.GetStream()
        $script:writer = New-Object System.IO.StreamWriter($script:stream)
        $script:writer.AutoFlush = $true
        $script:connected = $true
        Write-Log 'connected to Renode monitor'
        foreach ($name in $buttons.Keys) {
            $b = $buttons[$name]
            $level = if ($b[2]) { 'true' } else { 'false' }
            $script:writer.WriteLine("$($b[0]) OnGPIO $($b[1]) $level")
        }
        $script:statusLabel.Text = 'Connected - arrows / Enter / Backspace / Q'
    } catch {
        $script:connected = $false
        if ($script:client) { try { $script:client.Close() } catch { } }
        $script:client = $null; $script:stream = $null; $script:writer = $null
        $script:statusLabel.Text = 'Waiting for Renode...'
    }
}

function Send-Button([string]$name, [bool]$pressed) {
    if (-not $script:connected) { Connect-Monitor }
    if (-not $script:connected) { return }
    $b = $buttons[$name]
    if (-not $b) { return }
    if ($pressed -and $script:pressedButtons.Contains($name)) { return }
    if ((-not $pressed) -and (-not $script:pressedButtons.Contains($name))) { return }
    $level = if ($b[2]) { -not $pressed } else { $pressed }
    $val = if ($level) { 'true' } else { 'false' }
    try {
        $script:writer.WriteLine("$($b[0]) OnGPIO $($b[1]) $val")
        Write-Log "button $name pressed=$pressed -> $($b[0]) $($b[1]) $val"
    } catch {
        Write-Log "send failed: $($_.Exception.Message)"
        $script:connected = $false
        try { $script:client.Close() } catch { }
    }
    if ($pressed) {
        [void]$script:pressedButtons.Add($name)
        $script:buttonPressTime[$name] = [DateTime]::UtcNow
    } else {
        [void]$script:pressedButtons.Remove($name)
        $script:buttonPressTime.Remove($name)
    }
}

# Release a button as soon as the key/mouse is let go. Only a very short minimum
# hold (a few firmware ticks) is kept so that the firmware's input debounce
# always sees the press; the emulated firmware now runs in real time, so a
# normal click stays a short press and a held key becomes a long press.
$script:MinHoldMs = 50
function Request-Release([string]$name) {
    if (-not $script:pressedButtons.Contains($name)) { return }
    $t0 = $script:buttonPressTime[$name]
    $held = 1000
    if ($t0) { $held = ([DateTime]::UtcNow - $t0).TotalMilliseconds }
    if ($held -ge $script:MinHoldMs) {
        $script:pendingRelease.Remove($name)
        Send-Button $name $false
    } else {
        $script:pendingRelease[$name] = $true
    }
}

$form = New-Object System.Windows.Forms.Form
try { $form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance).SetValue($form, $true, $null) } catch { }
$form.Text = 'Flipper Zero Emulator'
$form.ClientSize = New-Object System.Drawing.Size(560, 440)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 16)
$form.KeyPreview = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

$screen = New-Object System.Windows.Forms.Panel
$screen.SetBounds(24, 24, 512, 256)
$screen.TabStop = $false
try { $screen.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance).SetValue($screen, $true, $null) } catch { }
$screen.BackColor = [System.Drawing.Color]::Black
$screen.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($screen)

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.SetBounds(24, 396, 512, 22)
$script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
$script:statusLabel.Text = 'Waiting for Renode...'
$form.Controls.Add($script:statusLabel)

$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.SetBounds(24, 286, 512, 108)
$btnPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 16)
$form.Controls.Add($btnPanel)

$script:pressedKeys = New-Object System.Collections.Generic.HashSet[string]
$script:pressedButtons = New-Object System.Collections.Generic.HashSet[string]
$script:pendingRelease = @{}
$script:buttonPressTime = @{}
$script:keyPressTime = @{}

# Layout like the real Flipper Zero: D-pad around a central OK, Back bottom-right.
$btnDefs = @(
    @{ Name='Up';    X=226; Y=4  },
    @{ Name='Left';  X=166; Y=38 },
    @{ Name='Ok';    X=226; Y=38 },
    @{ Name='Right'; X=286; Y=38 },
    @{ Name='Down';  X=226; Y=72 },
    @{ Name='Back';  X=418; Y=38 }
)
foreach ($bd in $btnDefs) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $bd.Name
    $b.SetBounds($bd.X, $bd.Y, 52, 28)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $b.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $b.Tag = $bd.Name
    $b.add_MouseDown({ param($s, $e) $form.ActiveControl = $null; Send-Button $s.Tag $true })
    $b.add_MouseUp({ param($s, $e) Request-Release $s.Tag })
    $b.add_MouseLeave({ param($s, $e) Request-Release $s.Tag })
    $btnPanel.Controls.Add($b)
}

$hint = New-Object System.Windows.Forms.Label
$hint.SetBounds(24, 420, 512, 18)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$hint.Text = 'Q = quit'
$form.Controls.Add($hint)

$script:fbBitmap = New-Object System.Drawing.Bitmap(128, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$script:fbExists = $false
$script:fbReader = New-Object ZeroFbReader -ArgumentList $FbPath
$script:fbReader.Start()

function Update-Frame {
    $pixels = $script:fbReader.GetPixelsIfNew()
    if ($null -eq $pixels) { return }
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, 128, 64)
        $bmpData = $script:fbBitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            [System.Runtime.InteropServices.Marshal]::Copy($pixels, 0, $bmpData.Scan0, 8192)
        } finally {
            $script:fbBitmap.UnlockBits($bmpData)
        }
        $script:fbExists = $true
        $screen.Invalidate()
    } catch { }
}

$screen.add_Paint({
    param($sender, $e)
    $e.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $e.Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    if ($script:fbExists) {
        $e.Graphics.DrawImage($script:fbBitmap, (New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)))
    } else {
        $e.Graphics.Clear([System.Drawing.Color]::Black)
        $font = New-Object System.Drawing.Font('Segoe UI', 10)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 140, 0))
        $e.Graphics.DrawString('Booting Flipper Zero...', $font, $brush, 12, 12)
        $font.Dispose(); $brush.Dispose()
    }
})

$form.add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Q) { $form.Close(); return }
    $keyStr = [string]$e.KeyCode
    $name = $keyMap[$keyStr]
    if (-not $name) { return }
    $e.Handled = $true
    $e.SuppressKeyPress = $true
    # Ignore the operating system's auto-repeat: one physical press = one press.
    if ($script:pressedKeys.Contains($keyStr)) { return }
    [void]$script:pressedKeys.Add($keyStr)
    Send-Button $name $true
})
$form.add_KeyUp({
    param($sender, $e)
    $keyStr = [string]$e.KeyCode
    [void]$script:pressedKeys.Remove($keyStr)
    $name = $keyMap[$keyStr]
    if ($name) { Request-Release $name; $e.Handled = $true }
})
$form.add_Shown({ $form.Activate(); $form.ActiveControl = $null })
$form.add_Deactivate({
    $script:pressedKeys.Clear()
    foreach ($bn in @($script:pressedButtons)) { Send-Button $bn $false }
    $script:pendingRelease.Clear()
})
$form.add_FormClosed({
    Write-Log 'viewer closed'
    try { $script:fbReader.Stop() } catch { }
    if ($script:client) { try { $script:client.Close() } catch { } }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15
$timer.add_Tick({
    Connect-Monitor
    Update-Frame
    $now = [DateTime]::UtcNow
    $toRelease = @()
    foreach ($bn in $script:pressedButtons) {
        $t0 = $script:buttonPressTime[$bn]
        if (-not $t0) { continue }
        $held = ($now - $t0).TotalMilliseconds
        if ($script:pendingRelease.ContainsKey($bn) -and $held -ge $script:MinHoldMs) { $toRelease += $bn }
        elseif ($held -ge 60000) { $toRelease += $bn }
    }
    foreach ($bn in $toRelease) {
        $script:pendingRelease.Remove($bn)
        Send-Button $bn $false
    }
})
$timer.Start()

[void]$form.ShowDialog()
$timer.Dispose()
$script:fbBitmap.Dispose()
'@

    $dfuCode = @'
#!/usr/bin/env python3
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
if len(data) < 11 or data[:5] != b"DfuSe":
    print("Not a DfuSe firmware file")
    sys.exit(2)

# The Flipper Zero firmware is shipped as a single DfuSe element whose
# target address is 0x08000000 (the start of internal flash).  Locate that
# element header directly instead of walking the (vendor-specific) target
# name field, which is not a standard null-terminated/length-prefixed string.
needle = struct.pack("<I", 0x08000000)
pos = data.find(needle)
if pos < 0:
    print("No application firmware found in the DFU file")
    sys.exit(3)

if pos + 8 > len(data):
    print("No application firmware found in the DFU file")
    sys.exit(3)

size = struct.unpack_from("<I", data, pos + 4)[0]
if size < 64 * 1024 or pos + 8 + size > len(data):
    print("No application firmware found in the DFU file")
    sys.exit(3)

raw = data[pos + 8:pos + 8 + size]
if len(raw) > 0x100000:
    raw = raw[:0x100000]
image = bytearray(b"\xff" * 0x100000)
image[:len(raw)] = raw
with open(dst, "wb") as f:
    f.write(image)
print("Firmware: %d bytes written to %s" % (len(raw), dst))
'@

    $resCode = @'
#!/usr/bin/env python3
import os
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile

img, res = sys.argv[1], sys.argv[2]
mount_point = tempfile.mkdtemp(prefix="flipres_")
subprocess.run(["mount", "-o", "loop", img, mount_point], check=True)
try:
    with tempfile.TemporaryDirectory(prefix="flipres_src_") as work:
        tar_path = res
        magic = open(res, "rb").read(4)
        if res.endswith(".ths") or magic == b"HSDS":
            try:
                import heatshrink2
            except ImportError:
                print("heatshrink2 is missing; cannot unpack .ths resources")
                sys.exit(2)
            data = open(res, "rb").read()
            _magic, _ver, window, lookahead = struct.unpack("<IBBB", data[:7])
            tar_path = os.path.join(work, "resources.tar")
            with open(tar_path, "wb") as f:
                f.write(heatshrink2.decompress(data[7:], window_sz2=window, lookahead_sz2=lookahead))
        with tarfile.open(tar_path, "r:*") as tar:
            try:
                tar.extractall(work, filter="data")
            except TypeError:
                tar.extractall(work)
        count = 0
        for name in sorted(os.listdir(work)):
            if name == "resources.tar":
                continue
            src = os.path.join(work, name)
            dst = os.path.join(mount_point, name)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
            count += 1
        print("Copied %d resource entries to the SD card" % count)
finally:
    subprocess.run(["sync"])
    subprocess.run(["umount", mount_point])
    os.rmdir(mount_point)
'@

    $timingPatchCode = @'
#!/usr/bin/env python3
# Flipper One Demo 7.11 - Flipper Zero emulator timing patch (idempotent).
#
# Problem: the stock firmware runs its FreeRTOS tick 2-7x faster than real
# time inside Renode, so a normal button click is seen as a long press.
# Cause: in tickless idle the firmware credits the sleep time from the
# LPTIM1 counter, but (a) it takes the "deep sleep" path which cannot work
# without the second core and (b) the LPTIM1 interrupt was never connected,
# so no sleep was ever ended by the timer.
#
# Fix (emulator side only, firmware untouched):
#   1. RTC backup registers start with a valid header + the firmware's
#      "legacy sleep" flag, so the firmware uses plain WFI light sleep.
#   2. LPTIM1 interrupt is connected to the NVIC (IRQ 47) so WFI is woken
#      by the timer exactly when the firmware asked for it.
#
# Usage: zero-timing-patch.py [emulator_dir]
import os
import re
import sys

MARK = "FLIPPER-ONE-DEMO-7.11"
base = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/flipper-zero-emulator")
failed = False


def read(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def backup(path):
    bak = path + ".orig"
    if not os.path.exists(bak):
        with open(path, "rb") as src, open(bak, "wb") as dst:
            dst.write(src.read())


def patch_rtc():
    path = os.path.join(base, "peripherals", "rtc_wb55.py")
    if not os.path.isfile(path):
        print("PATCH-ERROR: missing %s" % path)
        return False
    text = read(path)
    if MARK in text:
        print("rtc_wb55.py: already patched")
        return True
    nl = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    # Insert directly after the one-time creation of the backup register dict.
    m = re.search(r"(?m)^(?P<ind>[ \t]+)for i in range\(20\):\n(?P=ind)[ \t]+_bkp\[0x50 \+ i \* 4\] = 0[^\n]*\n", text)
    if not m:
        m = re.search(r"(?m)^(?P<ind>[ \t]+)_bkp = \{\}[^\n]*\n", text)
    if not m:
        print("PATCH-ERROR: rtc_wb55.py has an unexpected layout")
        return False
    ind = m.group("ind")
    add = (
        "%s# %s: valid header + Legacy Sleep flag -> firmware uses plain WFI sleep\n"
        "%s_bkp[0x50] = 0x000010F1   # header: magic 0x10F1, version 0\n"
        "%s_bkp[0x54] = 0x00002000   # SystemReg flags: LegacySleep\n"
    ) % (ind, MARK, ind, ind)
    text = text[: m.end()] + add + text[m.end():]
    backup(path)
    write(path, text.replace("\n", nl))
    print("rtc_wb55.py: patched")
    return True


def patch_rcc():
    path = os.path.join(base, "peripherals", "rcc_wb55.py")
    if not os.path.isfile(path):
        print("PATCH-ERROR: missing %s" % path)
        return False
    text = read(path)
    if MARK in text:
        print("rcc_wb55.py: already patched")
        return True
    nl = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    # Directly after the IER (0x40007C08) clear inside the LPTIM1RST emulation.
    m = re.search(r"(?m)^(?P<ind>[ \t]+)sysbus\.WriteDoubleWord\(\n[ \t]+System\.UInt64\(0x40007C08\), System\.UInt32\(0x0+\)\)[^\n]*\n", text)
    if not m:
        print("PATCH-ERROR: rcc_wb55.py has an unexpected layout")
        return False
    ind = m.group("ind")
    add = (
        "%s# %s: a real LPTIM reset also zeroes the counter (the Renode model\n"
        "%s# keeps the old CNT, which made the next sleep count too much time)\n"
        "%s_lp = sysbus.WhatPeripheralIsAt(System.UInt64(0x40007C00))\n"
        "%s_lp.ResetValue()\n"
    ) % (ind, MARK, ind, ind, ind)
    text = text[: m.end()] + add + text[m.end():]
    backup(path)
    write(path, text.replace("\n", nl))
    print("rcc_wb55.py: patched")
    return True


def patch_repl(path):
    if not os.path.isfile(path):
        return True
    text = read(path)
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^lptim1\s*:", ln):
            start = i
            break
    if start is None:
        print("PATCH-ERROR: no lptim1 block in %s" % os.path.basename(path))
        return False
    end = start + 1
    while end < len(lines) and (lines[end].strip() == "" or lines[end][:1] in (" ", "\t") or lines[end].startswith("//")):
        # blank line ends the block unless followed by more indented content
        if lines[end].strip() == "":
            break
        end += 1
    block = lines[start:end]
    for ln in block:
        if re.match(r"^\s*->\s*nvic@47\s*$", ln):
            print("%s: already patched" % os.path.basename(path))
            return True
    idx = None
    for j in range(start, end):
        if re.match(r"^\s*frequency\s*:", lines[j]):
            idx = j
    if idx is None:
        idx = start
    lines.insert(idx + 1, "    // %s: connect the idle timer IRQ so WFI wakes on time (real-time ticks)" % MARK)
    lines.insert(idx + 2, "    -> nvic@47")
    backup(path)
    write(path, nl.join(lines))
    print("%s: patched" % os.path.basename(path))
    return True


ok = patch_rtc()
ok = patch_rcc() and ok
ok = patch_repl(os.path.join(base, "platform", "stm32wb55_flipper.repl.in")) and ok
ok = patch_repl(os.path.join(base, "platform", "stm32wb55_flipper.repl")) and ok
if not ok:
    print("PATCH-FAILED")
    sys.exit(1)
print("TIMING-PATCH-OK")
'@

    $resetCode = @'
#!/bin/bash
set -e
cd ~/flipper-zero-emulator
python3 - <<'PY'
from pathlib import Path
src = Path('firmware/flipper-z-f7-full.bin')
if not src.exists():
    src = Path('firmware/flipper-z-f7-STOCK.bin')
if not src.exists():
    raise SystemExit('No bundled stock firmware found')
data = src.read_bytes()[:0x100000]
image = bytearray(b'\xff' * 0x100000)
image[:len(data)] = data
Path('firmware/flash.img').write_bytes(image)
print('Flash reset to bundled stock (%d bytes)' % len(data))
PY
'@

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $Root 'zero-viewer.ps1'), $viewerCode, $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'extract_dfu.py'), $dfuCode, $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'apply_resources.py'), $resCode, $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'zero-reset-flash.sh'), ($resetCode -replace "`r`n", "`n"), $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'zero-timing-patch.py'), ($timingPatchCode -replace "`r`n", "`n"), $utf8)
}

# Real-time fix (7.11): makes the emulated firmware's clock run at real Flipper
# Zero speed so that a normal click is no longer seen as a long press.
# Idempotent; applied before every start of the emulator.
function Invoke-ZeroTimingPatch {
    Write-ZeroHelperScripts
    $patchWsl = Get-ZeroWslPath (Join-Path $Root 'zero-timing-patch.py')
    $out = ''
    try { $out = (& wsl.exe -d FlipperOne -- python3 $patchWsl 2>&1 | Out-String) } catch { }
    if ($out -match 'TIMING-PATCH-OK') {
        if ($out -match 'patched' -and $out -notmatch 'already patched') { Say 'Applied the real-time timing fix to the emulator.' }
        return $true
    }
    Warn 'Could not apply the real-time timing fix; buttons may behave like long presses.'
    if ($out) { $out -split "`r?`n" | ForEach-Object { if ($_) { Say $_ } } }
    return $false
}

function Invoke-ZeroDownload {
    param([string]$Url, [string]$Dest)
    if ((Test-Path -LiteralPath $Dest) -and ((Get-Item -LiteralPath $Dest).Length -gt 0)) {
        Say "Using cached download: $([IO.Path]::GetFileName($Dest))"
        return $true
    }
    Say "Downloading $([IO.Path]::GetFileName($Dest)) ..."
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
        if ((Get-Item -LiteralPath $Dest).Length -le 0) { throw 'empty file' }
        Say ("Downloaded {0:N1} MB" -f ((Get-Item -LiteralPath $Dest).Length / 1MB))
        return $true
    } catch {
        Warn "Download failed: $($_.Exception.Message)"
        Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Expand-ZeroPackage {
    param([string]$Tgz, [string]$Dest)
    if (-not $Tgz -or -not (Test-Path -LiteralPath $Tgz)) { Warn 'Firmware package not found.'; return $false }
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $wslTgz = Get-ZeroWslPath $Tgz
    $wslDest = Get-ZeroWslPath $Dest
    if (-not $wslTgz -or -not $wslDest) { return $false }
    Say 'Extracting the firmware package ...'
    $out = & wsl.exe -d FlipperOne -- bash -c "rm -rf '$wslDest'/* 2>/dev/null; mkdir -p '$wslDest' && tar -xzf '$wslTgz' -C '$wslDest'" 2>&1
    if ($out) { $out | ForEach-Object { if ($_ -and $_ -notmatch '^\s*$') { Say $_ } } }
    if ($LASTEXITCODE -ne 0) { Warn 'Could not extract the firmware package.'; return $false }
    return $true
}

function Convert-ZeroDfuToBin {
    param([string]$Dfu, [string]$Bin)
    $scriptPath = Join-Path $Root 'extract_dfu.py'
    Write-ZeroHelperScripts
    $wslDfu = Get-ZeroWslPath $Dfu
    $wslBin = Get-ZeroWslPath $Bin
    $wslScript = Get-ZeroWslPath $scriptPath
    Say 'Converting firmware.dfu to a raw flash image ...'
    $out = & wsl.exe -d FlipperOne -- python3 $wslScript $wslDfu $wslBin 2>&1
    if ($out) { $out | ForEach-Object { if ($_) { Say $_ } } }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Bin)) {
        Warn 'Firmware conversion failed.'
        return $false
    }
    $size = (Get-Item -LiteralPath $Bin).Length
    if ($size -lt 65536 -or $size -gt 1048576) {
        Warn "Converted firmware has an unexpected size ($size bytes)."
        return $false
    }
    return $true
}

function Get-ZeroFirmwareFromExpanded {
    param([string]$Dir, [string]$Label)
    $dfu = Get-ChildItem -LiteralPath $Dir -Recurse -Filter 'firmware.dfu' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dfu) { Warn 'The firmware package does not contain firmware.dfu.'; return $null }
    $bin = Join-Path $dfu.DirectoryName 'firmware.bin'
    if (-not (Convert-ZeroDfuToBin -Dfu $dfu.FullName -Bin $bin)) { return $null }
    $res = Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^resources\.(tar|ths|tar\.gz)$' } | Select-Object -First 1
    return [pscustomobject]@{
        Bin       = $bin
        Resources = $(if ($res) { $res.FullName } else { $null })
        Label     = $Label
    }
}

function Get-ZeroFirmware {
    param([string]$Branch, [string]$CustomPath)
    $destDir = Join-Path $env:TEMP 'ZeroFirmware'
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    if ($Branch -eq 'custom') {
        if (-not $CustomPath -or -not (Test-Path -LiteralPath $CustomPath)) {
            Warn 'The selected custom firmware file was not found.'
            return $null
        }
        $ext = [IO.Path]::GetExtension($CustomPath).ToLowerInvariant()
        if ($ext -eq '.bin') {
            $size = (Get-Item -LiteralPath $CustomPath).Length
            if ($size -lt 65536 -or $size -gt 1048576) {
                Warn "The firmware file has an unexpected size ($size bytes)."
                return $null
            }
            return [pscustomobject]@{ Bin = $CustomPath; Resources = $null; Label = [IO.Path]::GetFileName($CustomPath) }
        }
        if ($ext -eq '.tgz' -or $ext -eq '.tar.gz') {
            $work = Join-Path $destDir ('custom-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            if (-not (Expand-ZeroPackage -Tgz $CustomPath -Dest $work)) { return $null }
            return (Get-ZeroFirmwareFromExpanded -Dir $work -Label ([IO.Path]::GetFileName($CustomPath)))
        }
        if ($ext -eq '.dfu') {
            $bin = Join-Path $destDir ('custom-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.bin')
            if (-not (Convert-ZeroDfuToBin -Dfu $CustomPath -Bin $bin)) { return $null }
            return [pscustomobject]@{ Bin = $bin; Resources = $null; Label = [IO.Path]::GetFileName($CustomPath) }
        }
        Warn 'Unsupported firmware file. Choose a .bin, .dfu or .tgz file.'
        return $null
    }

    if ($Branch -eq 'momentum') {
        try {
            $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/Next-Flip/Momentum-Firmware/releases/latest' -Headers @{'User-Agent'='FlipperOneDemo'}
            $asset = $r.assets | Where-Object { $_.name -like '*.tgz' } | Select-Object -First 1
            if (-not $asset) { Warn 'No Momentum firmware .tgz found.'; return $null }
            $tgz = Join-Path $destDir ('momentum-' + $r.tag_name + '.tgz')
            if (-not (Invoke-ZeroDownload -Url $asset.browser_download_url -Dest $tgz)) { return $null }
            $work = Join-Path $destDir ('momentum-' + $r.tag_name)
            if (-not (Expand-ZeroPackage -Tgz $tgz -Dest $work)) { return $null }
            return (Get-ZeroFirmwareFromExpanded -Dir $work -Label ('Momentum ' + $r.tag_name))
        } catch {
            Warn "Momentum firmware failed: $($_.Exception.Message)"
            return $null
        }
    }

    $officialVersion = $script:ZeroOfficialVersion
    $binUrl = "https://update.flipperzero.one/builds/firmware/$officialVersion/flipper-z-f7-full-$officialVersion.bin"
    $tgzUrl = "https://update.flipperzero.one/builds/firmware/$officialVersion/flipper-z-f7-update-$officialVersion.tgz"
    $bin = Join-Path $destDir "flipper-official-$officialVersion.bin"
    $tgz = Join-Path $destDir "flipper-official-$officialVersion.tgz"
    if (-not (Invoke-ZeroDownload -Url $binUrl -Dest $bin)) { return $null }
    $res = $null
    if (Invoke-ZeroDownload -Url $tgzUrl -Dest $tgz) {
        $work = Join-Path $destDir "official-resources-$officialVersion"
        if (Expand-ZeroPackage -Tgz $tgz -Dest $work) {
            $found = Get-ChildItem -LiteralPath $work -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^resources\.(tar|ths|tar\.gz)$' } | Select-Object -First 1
            if ($found) { $res = $found.FullName }
        }
    }
    return [pscustomobject]@{ Bin = $bin; Resources = $res; Label = "Official $officialVersion" }
}

function Install-ZeroResources {
    param([string]$Resources)
    if (-not $Resources -or -not (Test-Path -LiteralPath $Resources)) { return $true }
    $scriptPath = Join-Path $Root 'apply_resources.py'
    Write-ZeroHelperScripts
    $wslScript = Get-ZeroWslPath $scriptPath
    $wslRes = Get-ZeroWslPath $Resources
    $sd = '/root/flipper-zero-emulator/sdcard/sdcard.img'
    Say 'Installing firmware resources on the emulated SD card ...'
    $check = & wsl.exe -d FlipperOne -- bash -c "test -f $sd && echo YES || echo NO" 2>&1
    if ($check -notmatch 'YES') {
        Say 'Creating the emulated SD card ...'
        & wsl.exe -d FlipperOne -- bash -c "cd ~/flipper-zero-emulator && python3 scripts/prepare_sdcard.py --no-resources" 2>&1 | ForEach-Object { if ($_) { Say $_ } }
        if ($LASTEXITCODE -ne 0) { Warn 'Could not create the emulated SD card.'; return $false }
    }
    $out = & wsl.exe -d FlipperOne -- python3 $wslScript $sd $wslRes 2>&1
    if ($out) { $out | ForEach-Object { if ($_) { Say $_ } } }
    if ($LASTEXITCODE -ne 0) { Warn 'Could not install the firmware resources.'; return $false }
    return $true
}

function Stop-ZeroEmulator {
    param([switch]$Quiet)
    if (-not $Quiet) { Say 'Stopping the Flipper Zero emulator ...' }
    $viewerPid = Read-ZeroPid $script:ZeroViewerPidFile
    if ($viewerPid) { Stop-Process -Id $viewerPid -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $script:ZeroViewerPidFile -Force -ErrorAction SilentlyContinue
    $runPid = Read-ZeroPid $script:ZeroRunPidFile
    if ($runPid) {
        try { & taskkill.exe /PID $runPid /T /F 2>&1 | Out-Null } catch { }
    }
    Remove-Item -LiteralPath $script:ZeroRunPidFile -Force -ErrorAction SilentlyContinue
    try {
        & wsl.exe -d FlipperOne -- bash -c "pkill -9 -f '[s]dl_frontend.py' 2>/dev/null; pkill -9 -f '[t]ools/renode/renode' 2>/dev/null; pkill -9 -f '[r]un_updater.resc' 2>/dev/null; pkill -9 -f '[r]un.sh' 2>/dev/null; true" 2>&1 | Out-Null
    } catch { }
    Start-Sleep -Seconds 2
    $still = ''
    try { $still = & wsl.exe -d FlipperOne -- bash -c "pgrep -f '[t]ools/renode/renode' >/dev/null && echo YES || echo NO" 2>&1 } catch { }
    if ($still -match 'YES') {
        Say 'Renode is still running; stopping the FlipperOne Linux environment.'
        & wsl.exe --terminate FlipperOne 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }
    Remove-Item -LiteralPath (Join-Path $Root 'zero-fb.raw') -Force -ErrorAction SilentlyContinue
    if (-not $Quiet) { Say 'Flipper Zero emulator stopped.' }
}

function Start-ZeroViewer {
    if (-not (Test-ZeroRunning)) {
        Warn 'The Flipper Zero emulator is not running. Click "Run Emulator" first.'
        return $false
    }
    $viewer = Join-Path $Root 'zero-viewer.ps1'
    Write-ZeroHelperScripts
    $old = Read-ZeroPid $script:ZeroViewerPidFile
    if ($old) { Stop-Process -Id $old -Force -ErrorAction SilentlyContinue }
    $fb = '\\wsl.localhost\FlipperOne\tmp\flipper_fb.raw'
    $log = Join-Path $Root 'zero-viewer.log'
    $args = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -FbPath "{1}" -Port 1234 -LogPath "{2}"' -f $viewer, $fb, $log
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    $p.Id | Set-Content -LiteralPath $script:ZeroViewerPidFile -Encoding ASCII
    Say 'Flipper Zero display opened.'
    return $true
}

function Run-ZeroEmulator {
    if (-not (Test-ZeroInstalled -Refresh)) {
        Warn 'The Flipper Zero emulator is not installed. Click "Install Emulator" first.'
        return $false
    }
    Say 'Starting the Flipper Zero emulator ...'
    Write-ZeroHelperScripts
    $branch = [string]$script:ZeroBranch
    if (-not $branch) { $branch = 'official' }
    if ($branch -eq 'custom file') { $branch = 'custom' }
    $custom = [string]$script:ZeroCustomFirmware
    Say "Firmware source: $branch"
    $fw = Get-ZeroFirmware -Branch $branch -CustomPath $custom
    if (-not $fw) { Warn 'Firmware preparation failed.'; return $false }
    Say ("Firmware ready: {0} ({1:N0} KB)" -f $fw.Label, ((Get-Item -LiteralPath $fw.Bin).Length / 1KB))
    Stop-ZeroEmulator -Quiet
    $null = Invoke-ZeroTimingPatch
    if ($fw.Resources) { $null = Install-ZeroResources -Resources $fw.Resources }
    $sd = '/root/flipper-zero-emulator/sdcard/sdcard.img'
    $check = & wsl.exe -d FlipperOne -- bash -c "test -f $sd && echo YES || echo NO" 2>&1
    if ($check -notmatch 'YES') {
        Say 'Creating the emulated SD card ...'
        & wsl.exe -d FlipperOne -- bash -c "cd ~/flipper-zero-emulator && python3 scripts/prepare_sdcard.py --no-resources" 2>&1 | ForEach-Object { if ($_) { Say $_ } }
        if ($LASTEXITCODE -ne 0) { Warn 'Could not create the emulated SD card.'; return $false }
    }
    Write-ZeroHelperScripts
    $binWsl = Get-ZeroWslPath $fw.Bin
    $logWin = Join-Path $Root 'zero-run.log'
    $logWsl = Get-ZeroWslPath $logWin
    $runScript = Join-Path $Root 'zero-run.sh'
    $runText = @"
#!/bin/bash
set -e
cd ~/flipper-zero-emulator
export FLIPPER_EMU_MONITOR_PORT=1234
exec ./run.sh '$binWsl' --no-gui > '$logWsl' 2>&1
"@
    [IO.File]::WriteAllText($runScript, ($runText -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Remove-Item -LiteralPath $logWin -Force -ErrorAction SilentlyContinue
    $wslRun = Get-ZeroWslPath $runScript
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d','FlipperOne','--','bash',$wslRun) -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content -LiteralPath $script:ZeroRunPidFile -Encoding ASCII
    Start-Sleep -Seconds 3
    if ($proc.HasExited) {
        Warn "The emulator process exited immediately (code $($proc.ExitCode))."
        if (Test-Path -LiteralPath $logWin) {
            Get-Content -LiteralPath $logWin -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Say $_ }
        }
        Remove-Item -LiteralPath $script:ZeroRunPidFile -Force -ErrorAction SilentlyContinue
        return $false
    }
    Say "Emulator started (PID $($proc.Id)). Booting the firmware ..."
    $null = Start-ZeroViewer
    return $true
}

function Reset-ZeroFlash {
    if (-not (Test-ZeroInstalled -Refresh)) { Warn 'The Flipper Zero emulator is not installed.'; return $false }
    Say 'Resetting the Flipper Zero flash to the bundled stock firmware ...'
    Stop-ZeroEmulator -Quiet
    Write-ZeroHelperScripts
    $scriptPath = Get-ZeroWslPath (Join-Path $Root 'zero-reset-flash.sh')
    $out = & wsl.exe -d FlipperOne -- bash $scriptPath 2>&1
    if ($out) { $out | ForEach-Object { if ($_) { Say $_ } } }
    if ($LASTEXITCODE -ne 0) { Warn 'Flash reset failed.'; return $false }
    Say 'Flash reset. The next Run boots the stock firmware unless you choose another firmware.'
    return $true
}

function Install-ZeroEmulator {
    # The emulator lives in the private Linux environment. When that environment
    # does not exist yet (for example after "Uninstall Everything"), it is created
    # first. Nothing of the Flipper One part has to be installed for that.
    New-Item -ItemType Directory -Force -Path $Root, $DlDir, $DistroDir, $ToolsDir | Out-Null
    $null = Ensure-Wsl
    if (-not (Test-DistroHealthy)) {
        Assert-Space 8 'The Flipper Zero emulator'
        $null = Ensure-Distro
    }
    Say 'Installing the Flipper Zero emulator (Renode) in WSL ...'
    Say 'This may take 15-30 minutes. Use Cancel to abort.'
    $sh = Join-Path $env:TEMP 'install-zero.sh'
    $lines = @(
        '#!/bin/bash',
        'set -e',
        'export DEBIAN_FRONTEND=noninteractive',
        'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi',
        'cd ~',
        'echo "=== Step 1: Install base tools ==="',
        '$SUDO apt-get update -y',
        '$SUDO apt-get install -y git ca-certificates curl dosfstools mtools python3 python3-pip',
        'echo "=== Step 2: Clone repository ==="',
        'if [ ! -d flipper-zero-emulator ]; then',
        '  git clone --depth 1 https://github.com/d4rks1d33/Flipper-Zero-Emulator.git flipper-zero-emulator',
        'else',
        '  echo "Repository already present."',
        'fi',
        'cd flipper-zero-emulator',
        'echo "=== Step 3: Run install.sh ==="',
        './install.sh',
        'echo "=== Step 4: Run setup.sh ==="',
        './setup.sh',
        'echo "ZERO_INSTALLED_OK"'
    )
    $script_content = $lines -join "`n"
    [IO.File]::WriteAllText($sh, $script_content, (New-Object System.Text.UTF8Encoding($false)))
    $wslSh = (& wsl.exe -d FlipperOne -e wslpath -a $sh 2>&1)
    if (-not $wslSh -or $wslSh -match 'error|not found') { $wslSh = $sh }
    Say 'Running the install script in WSL ...'
    & wsl.exe -d FlipperOne -- bash $wslSh | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Warn "Installation failed with exit code $LASTEXITCODE. Check the activity log."
        return $false
    }
    if (-not (Test-ZeroInstalled -Refresh)) {
        Warn 'The installer finished, but the emulator files were not found. Check the activity log.'
        return $false
    }
    $null = Invoke-ZeroTimingPatch
    Say 'Flipper Zero emulator installed successfully.'
    return $true
}

# Removes only the Flipper Zero emulator (not the Linux environment or Flipper One).
function Remove-ZeroEmulatorFiles {
    Stop-ZeroEmulator -Quiet
    Say 'Removing the installed Flipper Zero emulator ...'
    try {
        if (Test-Distro) {
            & wsl.exe -d $Distro -- bash -c "rm -rf ~/flipper-zero-emulator /tmp/flipper_fb.raw" 2>&1 | Out-Null
        }
    } catch { }
    Remove-Item -LiteralPath $script:ZeroFlag -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:TEMP 'ZeroFirmware') -Recurse -Force -ErrorAction SilentlyContinue
    $script:ZeroInstalled = $false
}

function Reinstall-ZeroEmulator {
    Remove-ZeroEmulatorFiles
    return (Install-ZeroEmulator)
}

# Files the app may have put outside its own folder. Used by "Uninstall Everything".
function Remove-FlipperLeftovers {
    $ok = $true
    $targets = @($FilesMirror, (Join-Path $env:TEMP 'ZeroFirmware'), (Join-Path $env:TEMP 'install-zero.sh'))
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        for ($i = 0; $i -lt 8; $i++) {
            Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $t)) { break }
            Start-Sleep -Milliseconds 500
        }
        if (Test-Path -LiteralPath $t) { Warn "Could not remove: $t"; $ok = $false }
    }
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'FlipperOneDemo-*.bat' -File -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $uiPrefix = 'FlipperOneDemo-ui-'
    Get-ChildItem -LiteralPath $env:TEMP -Filter ($uiPrefix + '*') -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $idText = $_.Name.Substring($uiPrefix.Length)
        $alive = $false
        if ($idText -match '^\d+$') {
            if (Get-Process -Id ([int]$idText) -ErrorAction SilentlyContinue) { $alive = $true }
        }
        if (-not $alive) { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $ok
}

function Show-Ui {
    try {
        Initialize-UiTypes
    } catch {
        $detail = $_.Exception.Message
        try { Add-Type -AssemblyName System.Windows.Forms } catch { }
        [void][System.Windows.Forms.MessageBox]::Show("The app window could not be prepared.`n`n" + $detail,
            'Flipper Emulator', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    try {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    } catch { }
    try {
        Initialize-UiWorkspace
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("The app window could not be prepared.`n`n" + $_.Exception.Message,
            'Flipper Emulator', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $script:UiBusy = $false
    $script:UiProcess = $null
    $script:UiLogPath = $null
    $script:UiLogChars = 0
    $script:UiLogText = ''
    $script:UiAction = ''
    $script:UiMode = 'one'
    $script:UiOneCache = $null
    $script:UiLastStatus = [DateTime]::MinValue

    $imgOne = [FlipImages]::FromBase64($script:UiImgOne)
    $imgZero = [FlipImages]::FromBase64($script:UiImgZero)
    $form = New-Object FlipperMainForm -ArgumentList @($Version, $imgOne, $imgZero)
    $script:UiForm = $form
    $script:UiLogBox = $form.LogBox
    $form.SetOfficialLabel('Official ' + $script:ZeroOfficialVersion)

    $form.add_ActionRequested({
        param($sender, $eventArgs)
        try {
            Invoke-UiAction ([string]$sender.RequestedAction)
        } catch {
            Add-UiLogMessage ('Error: ' + $_.Exception.Message)
            Set-UiActivity 'Needs attention' 'Danger'
        }
    })
    $form.add_FirmwareChanged({
        param($sender, $eventArgs)
        switch ($sender.FirmwareIndex) {
            1 { $script:ZeroBranch = 'momentum' }
            2 { $script:ZeroBranch = 'custom' }
            default { $script:ZeroBranch = 'official' }
        }
    })
    $form.add_ModeChanged({
        param($sender, $eventArgs)
        if ($sender.IsZeroMode) { $script:UiMode = 'zero' } else { $script:UiMode = 'one' }
        if ($script:UiBusy) { return }
        if ($script:UiMode -eq 'zero') {
            Refresh-ZeroUiStatus
        } else {
            Apply-UiOneStatus
            # The full check runs a moment later, after the colour fade has finished.
            $script:UiLastStatus = (Get-Date).AddSeconds(-4.2)
        }
    })

    $form.add_Shown({
        Refresh-UiStatus
        $script:UiLastStatus = Get-Date
        Add-UiLogMessage "Flipper Emulator $Version is ready."
    })
    $form.add_FormClosing({
        param($sender, $eventArgs)
        if ($script:UiBusy) {
            $answer = [System.Windows.Forms.MessageBox]::Show($sender,
                "An operation is still running.`n`nClose this window anyway? The operation will continue in the background.",
                'Close Flipper Emulator',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                $eventArgs.Cancel = $true
                return
            }
        }
        if ($script:UiTimer) { $script:UiTimer.Stop() }
    })
    $form.add_FormClosed({
        if ($script:UiTimer) {
            try { $script:UiTimer.Dispose() } catch { }
            $script:UiTimer = $null
        }
        if (-not $script:UiBusy -and $script:UiWork) {
            Remove-Item -LiteralPath $script:UiWork -Recurse -Force -ErrorAction SilentlyContinue
        }
    })
    $form.add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F5 -and -not $script:UiBusy) {
            Invoke-UiAction 'refresh'
            $eventArgs.Handled = $true
        }
    })

    $script:UiTimer = New-Object System.Windows.Forms.Timer
    $script:UiTimer.Interval = 650
    $script:UiTimer.add_Tick({ Update-Ui })
    $script:UiTimer.Start()

    [void]$form.ShowDialog()
    try { $form.Dispose() } catch { }
    $script:UiForm = $null
    $script:UiLogBox = $null
    if (-not $script:UiBusy -and $script:UiWork) {
        for ($i = 0; $i -lt 6; $i++) {
            Remove-Item -LiteralPath $script:UiWork -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $script:UiWork)) { break }
            Start-Sleep -Milliseconds 150
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$cmd = ''
if ($env:FLIP_ARGS) { $cmd = $env:FLIP_ARGS.Trim().ToLower() }

# No arguments opens the Windows app. The console menu remains available with
# the hidden "menu" argument and every existing command-line action is unchanged.
if ($cmd -eq '' -or $cmd -eq 'gui') { Show-Ui; exit 0 }
if ($cmd -eq 'menu') { Show-Menu; exit 0 }

# Actions launched by the Windows app. They run in a hidden child process and
# never wait for keyboard input.
if ($cmd -eq 'ui-preview') { Start-Demo; exit 0 }
if ($cmd -eq 'ui-real') { Start-RealOS; exit 0 }
if ($cmd -eq 'ui-files') { Open-FileShelf; exit 0 }
if ($cmd -eq 'ui-stop') { Stop-Demo; Start-Sleep -Seconds 2; exit 0 }
if ($cmd -eq 'ui-log') { Show-Log; exit 0 }
if ($cmd -eq 'ui-uninstall') { $null = Uninstall-All -NoConfirm; exit 0 }
if ($cmd -eq 'ui-reset') { $null = Reset-Flipper -NoConfirm; exit 0 }
if ($cmd -eq 'ui-reinstall') { Reinstall-All -NoConfirm; exit 0 }
if ($cmd -eq 'ui-wipe') {
    $res = @(Uninstall-All -NoConfirm -Wipe)
    if ($res.Count -gt 0 -and $res[-1] -eq $true) { exit 0 }
    exit 1
}
if ($cmd -eq 'ui-zero-install') {
    $res = @(Install-ZeroEmulator)
    if ($res.Count -gt 0 -and $res[-1] -eq $true) { exit 0 }
    exit 1
}
if ($cmd -eq 'ui-zero-reinstall') {
    $res = @(Reinstall-ZeroEmulator)
    if ($res.Count -gt 0 -and $res[-1] -eq $true) { exit 0 }
    exit 1
}
if ($cmd -eq 'ui-zero-run') {
    $selFile = Join-Path $Root 'zero-selection.json'
    if (Test-Path -LiteralPath $selFile) {
        try {
            $sel = Get-Content -LiteralPath $selFile -Raw | ConvertFrom-Json
            if ($sel.branch) { $script:ZeroBranch = [string]$sel.branch }
            if ($sel.custom) { $script:ZeroCustomFirmware = [string]$sel.custom }
        } catch { }
    }
    $res = @(Run-ZeroEmulator)
    if ($res.Count -gt 0 -and $res[-1] -eq $true) { exit 0 }
    exit 1
}
if ($cmd -eq 'ui-zero-show') { $null = Start-ZeroViewer; exit 0 }
if ($cmd -eq 'ui-zero-stop') { Stop-ZeroEmulator; exit 0 }
if ($cmd -eq 'ui-zero-reset') { Reset-ZeroFlash; exit 0 }
if ($cmd -eq 'powermeter' -or $cmd -eq 'demo' -or $cmd -eq 'power') { Start-Process 'https://dev.repetren.com/power_meter_demo/'; Write-Host 'Opened the Power Meter demo in your browser.'; exit 0 }

Write-Host ''
Write-Host "=== Flipper Emulator v$Version ===" -ForegroundColor Yellow
Write-Host 'Unofficial community helper - not affiliated with Flipper Devices.' -ForegroundColor DarkGray
Write-Host 'Option 1: FlipCTL preview (fast, stable).'
Write-Host 'Option 2: real Flipper OS in QEMU (experimental, slow).'
Write-Host 'Option 3: Flipper OS + File Manager (starts what is missing, opens both).'
Write-Host 'Option 8: factory reset of the real Flipper OS (deletes apps and files).'

if ($cmd -eq 'stop') { Stop-Demo; Start-Sleep -Seconds 2; exit 0 }
if ($cmd -eq 'real' -or $cmd -eq 'realos') { Start-RealOS; exit 0 }
if ($cmd -eq 'files') { Open-FileShelf; exit 0 }
if ($cmd -eq 'backup') {
    New-Item -ItemType Directory -Force -Path $FilesMirror | Out-Null
    Start-Process explorer.exe $FilesMirror
    exit 0
}
if ($cmd -eq 'start') { Start-Demo; exit 0 }
if ($cmd -eq 'log') { Show-Log; exit 0 }
if ($cmd -eq 'wipe') { $null = Uninstall-All -Wipe; exit 0 }
if ($cmd -eq 'uninstall') { $null = Uninstall-All -NoConfirm; exit 0 }
if ($cmd -eq 'reset') { $null = Reset-Flipper; exit 0 }
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
            $null = Sync-GuestFiles -Mode Import
            if (-not (Get-QemuPath)) { $null = Install-QemuPortable }
            Start-RealOS
        } else { Start-Demo }
    }
    exit 0
}
if ($cmd -eq 'resume') {
    try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FlipperOneDemoResume' -Force -ErrorAction SilentlyContinue } catch { }
    Install-All
    Show-Ui
    exit 0
}

if (-not ((Test-Path $InstalledFlag) -and (Test-DistroHealthy))) {
    Write-Host ''
    Write-Host 'First start: everything needed is downloaded and set up automatically.' -ForegroundColor Green
    Write-Host 'This can take a few minutes and needs about 12 GB of free disk space.' -ForegroundColor Green
    Write-Host 'Option 1 needs no administrator rights. Option 2 uses QEMU (portable if needed).' -ForegroundColor Green
    Write-Host 'Windows may ask once for permission to enable WSL.' -ForegroundColor Green
}
Show-Menu
