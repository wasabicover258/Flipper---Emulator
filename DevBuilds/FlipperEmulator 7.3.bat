@echo off
setlocal
title Flipper One Demo v7.3
rem Flipper One Demo - unofficial community helper, v7.3 development build
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
# Flipper One Demo - unofficial community helper (v7.2 development build)
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

$Version       = '7.3'
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

VERSION = "7.3"
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
    param([switch]$NoConfirm, [switch]$KeepBackup)
    if (-not $NoConfirm) {
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
    if ((Test-Path $ShelfFlag) -and (Test-Path $RealRaw)) {
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
        Write-Host 'Please close all browser windows and try option 5 again.' -ForegroundColor Yellow
        return $false
    }
    if ($distroLeft) {
        Warn 'The private Linux environment could not be removed. Please restart Windows and try option 5 again.'
        return $false
    }
    if ($scheduled) {
        Say 'Everything has been removed. The last temporary file is cleaned up when this window closes.'
    } else {
        Say 'Everything has been removed.'
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
        Write-Host 'Reset confirmed in the Flipper One Demo app.' -ForegroundColor Green
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
        Write-Host 'Reinstall confirmed in the Flipper One Demo app.' -ForegroundColor Green
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
                'Flipper One Demo - File Manager',
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
$script:UiTimer         = $null
$script:UiLastStatus    = [DateTime]::MinValue
$script:UiCards         = New-Object System.Collections.ArrayList
$script:UiTheme        = 'one'
$script:UiMode         = 'one'
$script:UiCancelButton = $null
$script:UiZeroButtons  = $null
$script:UiZeroFirmwareCombo = $null
$script:ZeroCustomFirmware = ''
$script:ZeroBranch       = 'official'
$script:ZeroFirmwarePath  = $null
$script:UiImgOne = 'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAP+SURBVEhL7ZPNayNlHMdzWFFR8OBlD0vt0iaZTCeTSeY1ySSTt6bppElm8tL0Ja82bZM0262bSGkLuiJit7JY1u0WpVtRD0IbEI89SI8riwsi6sV/YD149eZ+ZSKWdqBnPewHfjwMfPk8z+/5zWOxPOd/yXubmxMPN1rb76+1tmu1xlGtXDs+X9VS9bharh436o1+vVrfymm5jK5n92dn5+6VS9WTerV+2+w8Y3d3lz88+Bzvbr2D0mwJy40mWksttJdX0F5uD9ZOs4NO6wZWmiuoVeoozVcwNZVGKBT5c3h4OBgKRg7z+fzLZveAne2dvS8Ov0S1UocsBzEeHUc6mUZOy51VXs8PVjWhGlKkUhpYloPHwz6TZZnVM7leu9B+1ey2AHjh7kd3n975cAcBWcFkIglREB8ThLVDkWTHRZIdiiQ6pNXaGRka6nBuzze6nkc8qYNyC2A8HHiWfxiLxbvdbvcVs9/SXes2P93/DJ2VVWT1HBITKkRePDDn/kWWlVYkPoWjVhCntwJwu91gOfEPzsMfnJ6eXrkQTiQSL2pp7emtt3rIFeZQri1icnIKXsn71YXgOayMv9fOxoCPOeA+h60sD7c3hExaPzFnLdlMVi3kZzA1qUIPMNBlGn6vBJ4XLt3gdbvQu1/1A5+E8OyBiuOWDKuTw8b65rfmrEXLZI+niyXkJ0KIcCRiEoNJmQXNeC7d4LURT+9BzQ/cU/DXYQVHN1VcfWME+Wzh5wtBRVFeUpTQ77FYHImgFxTNwOlyIyF7wHqYSze45hB6a3oA2AsCXzfwQTkKmvODopyPLwQVRbkiCN7fOE7EhI8FRbswRjNIBHjQTufhhfA5BEHqGH/Odzcl/Hp7HCLHIaUVjbk9MmctYSV6x+cPIerjkVcYFCI8Ij4edgd1QpO0LLLsWbFG0azscrn3RI4FYR3B8PVR7L8ZwkYlDRfn+97stySTSUr2B2F0IblIiDQBO0EYQ4bAC5BEyXgTkETROOE/36IXPEODGiNxzUrhydtebGosuMD4j2b/AK/X/6RYmEE0GjeGC1GUjPuE3W4HQRCw2Wyw2mxwOByw2W1wOmkIohcuFwMb4YDfRYAZI6CEIj+Z3QP0tJ5cXmyiOD2LXK6ApJpCWIkiGh5HWIkgKCsIykF4JR9EQYLHzSIciiIeT2B0dBRD10cwarXB7XL/YnafUSzMPFpsLGN+roxquYbyXBWd5iputFbRqC9iod5AY2EJ04UZKIGw8ahQKBQHHRpXanTsIMgfzN4zVLVwdW2tl9lc38wsNZorSwut/kJtqV+Zr/WL+Zm+ltL6qWS6n0wk+yk13dczuXVN00okSfWNcjpdfYqiVLP3Of8dfwNK9tXTOMVh8gAAAABJRU5ErkJggg=='
$script:UiImgZero = 'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYSURBVEhL7cEBDQAAAMKg90/t7AEUAAA3CRgAAQj7teIAAAAASUVORK5CYII='
$script:UiProgressDoneAt = $null

$script:UiColor = @{
    Background = '#0D0D0D'
    Sidebar    = '#141414'
    Card       = '#1C1C1C'
    Border     = '#333333'
    Text       = '#F2F2F2'
    Muted      = '#A0A0A0'
    Faint      = '#6B6B6B'
    Accent     = '#FF8C00'
    Success    = '#4CAF50'
    Warning    = '#FF8C00'
    Danger     = '#E53935'
    Blue       = '#FFB347'
    Orange     = '#FF6B35'
}

$script:UiColorOne = @{
    Background = '#0D0D0D'
    Sidebar    = '#141414'
    Card       = '#1C1C1C'
    Border     = '#333333'
    Text       = '#F2F2F2'
    Muted      = '#A0A0A0'
    Faint      = '#6B6B6B'
    Accent     = '#FF8C00'
    Success    = '#4CAF50'
    Warning    = '#FF8C00'
    Danger     = '#E53935'
    Blue       = '#FFB347'
    Orange     = '#FF6B35'
}

$script:UiColorZero = @{
    Background = '#0F1216'
    Sidebar    = '#14181D'
    Card       = '#1B2027'
    Border     = '#2E3540'
    Text       = '#F2F2F2'
    Muted      = '#A0A0A0'
    Faint      = '#6B6B6B'
    Accent     = '#FF8C00'
    Success    = '#4CAF50'
    Warning    = '#FF8C00'
    Danger     = '#E53935'
    Blue       = '#FFB347'
    Orange     = '#FF6B35'
}

function Get-UiColor([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function New-UiFont {
    param(
        [double]$Size = 9,
        [string]$Family = 'Segoe UI',
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    return New-Object System.Drawing.Font($Family, [single]$Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function New-UiLabel {
    param(
        [string]$Text,
        [double]$Size = 9,
        [string]$Color = '#E2E8F0',
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [string]$Family = 'Segoe UI'
    )
    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $false
    $label.Text = $Text
    $label.Font = New-UiFont -Size $Size -Family $Family -Style $Style
    $label.ForeColor = Get-UiColor $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.UseMnemonic = $false
    return $label
}

function New-UiButton {
    param(
        [string]$Text,
        [int]$Width = 160,
        [int]$Height = 34,
        [string]$Accent = '#38BDF8'
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = $Height
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = Get-UiColor '#242424'
    $button.ForeColor = Get-UiColor '#E2E8F0'
    $button.Font = New-UiFont -Size 9 -Style ([System.Drawing.FontStyle]::Regular)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = Get-UiColor '#444444'
    $button.FlatAppearance.MouseOverBackColor = Get-UiColor '#2E2E2E'
    $button.FlatAppearance.MouseDownBackColor = Get-UiColor '#1A1A1A'
    return $button
}

function Initialize-UiTypes {
    if ('FlipperActionCard' -as [type]) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class FlipperActionCard : Panel
{
    public string ActionKey { get; private set; }
    public Color AccentColor { get; private set; }

    private readonly Label glyphLabel;
    private readonly Label titleLabel;
    private readonly Label descLabel;
    private readonly Label arrowLabel;
    private readonly Color normalColor = Color.FromArgb(28, 28, 28);
    private readonly Color hoverColor = Color.FromArgb(40, 40, 40);
    private readonly Color pressColor = Color.FromArgb(16, 16, 16);
    private readonly Color normalTitle = Color.FromArgb(242, 242, 242);
    private readonly Color normalText = Color.FromArgb(160, 160, 160);
    private bool isHover;
    private bool isPressed;

    public FlipperActionCard(string actionKey, string title, string description, string glyph, Color accent)
    {
        ActionKey = actionKey;
        AccentColor = accent;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        Margin = new Padding(6);
        MinimumSize = new Size(180, 100);
        AccessibleName = title;

        glyphLabel = new Label();
        glyphLabel.Text = glyph;
        glyphLabel.Font = new Font("Segoe UI Symbol", 16.5f, FontStyle.Regular, GraphicsUnit.Point);
        glyphLabel.ForeColor = accent;
        glyphLabel.TextAlign = ContentAlignment.MiddleCenter;
        glyphLabel.BackColor = normalColor;

        titleLabel = new Label();
        titleLabel.Text = title;
        titleLabel.Font = new Font("Segoe UI Semibold", 11.5f, FontStyle.Regular, GraphicsUnit.Point);
        titleLabel.ForeColor = normalTitle;
        titleLabel.TextAlign = ContentAlignment.MiddleLeft;
        titleLabel.AutoEllipsis = true;
        titleLabel.BackColor = normalColor;

        descLabel = new Label();
        descLabel.Text = description;
        descLabel.Font = new Font("Segoe UI", 8.75f, FontStyle.Regular, GraphicsUnit.Point);
        descLabel.ForeColor = normalText;
        descLabel.TextAlign = ContentAlignment.TopLeft;
        descLabel.BackColor = normalColor;

        arrowLabel = new Label();
        arrowLabel.Text = ">";
        arrowLabel.Font = new Font("Segoe UI Semibold", 12f, FontStyle.Regular, GraphicsUnit.Point);
        arrowLabel.ForeColor = Color.FromArgb(107, 107, 107);
        arrowLabel.TextAlign = ContentAlignment.MiddleCenter;
        arrowLabel.BackColor = normalColor;

        Controls.Add(glyphLabel);
        Controls.Add(titleLabel);
        Controls.Add(descLabel);
        Controls.Add(arrowLabel);
        Attach(this);
        Attach(glyphLabel);
        Attach(titleLabel);
        Attach(descLabel);
        Attach(arrowLabel);
        LayoutChildren();
    }

    private void Attach(Control control)
    {
        control.Cursor = Cursors.Hand;
        control.MouseEnter += delegate { SetHover(true); };
        control.MouseLeave += delegate
        {
            if (!ClientRectangle.Contains(PointToClient(Cursor.Position))) { SetHover(false); }
        };
        control.MouseDown += delegate
        {
            if (Enabled) { isPressed = true; Invalidate(); }
        };
        control.MouseUp += delegate
        {
            isPressed = false;
            Invalidate();
        };
        control.Click += delegate
        {
            if (!Enabled) { return; }
            EventHandler handler = ActionClicked;
            if (handler != null) { handler(this, EventArgs.Empty); }
        };
    }

    public event EventHandler ActionClicked;

    private void SetHover(bool value)
    {
        if (!Enabled) { value = false; }
        if (isHover == value) { return; }
        isHover = value;
        UpdateChildColors();
        Invalidate();
    }

    private void UpdateChildColors()
    {
        Color background = isPressed ? pressColor : (isHover ? hoverColor : normalColor);
        Color title = Enabled ? normalTitle : Color.FromArgb(107, 107, 107);
        Color text = Enabled ? normalText : Color.FromArgb(107, 107, 107);
        foreach (Control control in Controls) { control.BackColor = background; }
        titleLabel.ForeColor = title;
        glyphLabel.ForeColor = Enabled ? AccentColor : Color.FromArgb(107, 107, 107);
        descLabel.ForeColor = text;
        arrowLabel.ForeColor = isHover && Enabled ? AccentColor : Color.FromArgb(107, 107, 107);
    }

    protected override void OnEnabledChanged(EventArgs e)
    {
        base.OnEnabledChanged(e);
        foreach (Control control in Controls) { control.Cursor = Enabled ? Cursors.Hand : Cursors.Default; }
        if (!Enabled) { isHover = false; isPressed = false; }
        UpdateChildColors();
        Invalidate();
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        LayoutChildren();
    }

    private void LayoutChildren()
    {
        int width = Width;
        int height = Height;
        glyphLabel.SetBounds(16, 13, 30, 34);
        titleLabel.SetBounds(50, 13, Math.Max(30, width - 82), 26);
        arrowLabel.SetBounds(width - 29, 14, 16, 24);
        descLabel.SetBounds(17, 47, Math.Max(30, width - 34), Math.Max(24, height - 56));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Color fill = isPressed ? pressColor : (isHover ? hoverColor : normalColor);
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath path = RoundedRect(rect, 10))
        using (SolidBrush brush = new SolidBrush(fill))
        using (Pen border = new Pen(isHover && Enabled ? AccentColor : Color.FromArgb(51, 51, 51), 1f))
        {
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(border, path);
        }
        using (Pen accent = new Pen(Enabled ? AccentColor : Color.FromArgb(107, 107, 107), 3f))
        {
            accent.StartCap = LineCap.Round;
            accent.EndCap = LineCap.Round;
            e.Graphics.DrawLine(accent, 2.5f, 13f, 2.5f, Height - 13f);
        }
        base.OnPaint(e);
    }

    private static GraphicsPath RoundedRect(Rectangle rect, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

public sealed class FlipperConfirmDialog : Form
{
    public static bool Confirm(IWin32Window owner, string title, string heading, string body,
        string phrase, string confirmLabel, Color accent, bool caseSensitive)
    {
        using (FlipperConfirmDialog dialog = new FlipperConfirmDialog(title, heading, body, phrase, confirmLabel, accent, caseSensitive))
        {
            return dialog.ShowDialog(owner) == DialogResult.OK;
        }
    }

    private FlipperConfirmDialog(string title, string heading, string body,
        string phrase, string confirmLabel, Color accent, bool caseSensitive)
    {
        Text = title;
        ClientSize = new Size(548, 344);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        ShowIcon = false;
        BackColor = Color.FromArgb(13, 13, 13);
        ForeColor = Color.FromArgb(242, 242, 242);
        Font = new Font("Segoe UI", 9.5f, FontStyle.Regular, GraphicsUnit.Point);
        AutoScaleMode = AutoScaleMode.Dpi;

        Panel accentBar = new Panel();
        accentBar.Dock = DockStyle.Top;
        accentBar.Height = 4;
        accentBar.BackColor = accent;

        Label headingLabel = new Label();
        headingLabel.Text = heading;
        headingLabel.Font = new Font("Segoe UI Semibold", 16f, FontStyle.Regular, GraphicsUnit.Point);
        headingLabel.ForeColor = Color.FromArgb(242, 242, 242);
        headingLabel.SetBounds(26, 24, 496, 32);
        headingLabel.BackColor = BackColor;

        Label bodyLabel = new Label();
        bodyLabel.Text = body;
        bodyLabel.Font = new Font("Segoe UI", 9.25f, FontStyle.Regular, GraphicsUnit.Point);
        bodyLabel.ForeColor = Color.FromArgb(208, 208, 208);
        bodyLabel.SetBounds(26, 64, 496, 94);
        bodyLabel.BackColor = BackColor;

        Label promptLabel = new Label();
        promptLabel.Text = "Type " + phrase + " to continue";
        promptLabel.Font = new Font("Segoe UI Semibold", 9.5f, FontStyle.Regular, GraphicsUnit.Point);
        promptLabel.ForeColor = accent;
        promptLabel.SetBounds(26, 166, 496, 22);
        promptLabel.BackColor = BackColor;

        TextBox phraseBox = new TextBox();
        phraseBox.SetBounds(26, 192, 496, 30);
        phraseBox.BackColor = Color.FromArgb(10, 10, 10);
        phraseBox.ForeColor = Color.FromArgb(242, 242, 242);
        phraseBox.BorderStyle = BorderStyle.FixedSingle;
        phraseBox.Font = new Font("Consolas", 12f, FontStyle.Regular, GraphicsUnit.Point);

        Label hintLabel = new Label();
        hintLabel.Text = "The button becomes available when the word matches.";
        hintLabel.Font = new Font("Segoe UI", 8.25f, FontStyle.Regular, GraphicsUnit.Point);
        hintLabel.ForeColor = Color.FromArgb(107, 107, 107);
        hintLabel.SetBounds(26, 228, 496, 20);
        hintLabel.BackColor = BackColor;

        Button cancel = new Button();
        cancel.Text = "Cancel";
        cancel.SetBounds(298, 278, 106, 36);
        cancel.FlatStyle = FlatStyle.Flat;
        cancel.UseVisualStyleBackColor = false;
        cancel.BackColor = Color.FromArgb(36, 36, 36);
        cancel.ForeColor = Color.FromArgb(208, 208, 208);
        cancel.FlatAppearance.BorderSize = 1;
        cancel.FlatAppearance.BorderColor = Color.FromArgb(68, 68, 68);
        cancel.FlatAppearance.MouseOverBackColor = Color.FromArgb(46, 46, 46);
        cancel.Cursor = Cursors.Hand;
        cancel.DialogResult = DialogResult.Cancel;

        Button confirm = new Button();
        confirm.Text = confirmLabel;
        confirm.SetBounds(416, 278, 106, 36);
        confirm.FlatStyle = FlatStyle.Flat;
        confirm.UseVisualStyleBackColor = false;
        confirm.BackColor = Color.FromArgb(51, 51, 51);
        confirm.ForeColor = Color.FromArgb(208, 208, 208);
        confirm.FlatAppearance.BorderSize = 0;
        confirm.FlatAppearance.MouseOverBackColor = accent;
        confirm.Cursor = Cursors.Default;
        confirm.Enabled = false;

        confirm.Click += delegate
        {
            if (!confirm.Enabled) { return; }
            DialogResult = DialogResult.OK;
            Close();
        };
        phraseBox.TextChanged += delegate
        {
            bool ok = caseSensitive
                ? string.Equals(phraseBox.Text, phrase, StringComparison.Ordinal)
                : string.Equals(phraseBox.Text, phrase, StringComparison.OrdinalIgnoreCase);
            confirm.Enabled = ok;
            confirm.BackColor = ok ? accent : Color.FromArgb(51, 51, 51);
            confirm.ForeColor = ok ? Color.White : Color.FromArgb(160, 160, 160);
            confirm.Cursor = ok ? Cursors.Hand : Cursors.Default;
            confirm.FlatAppearance.MouseOverBackColor = ok ? accent : Color.FromArgb(51, 51, 51);
        };

        AcceptButton = confirm;
        CancelButton = cancel;
        Controls.Add(accentBar);
        Controls.Add(headingLabel);
        Controls.Add(bodyLabel);
        Controls.Add(promptLabel);
        Controls.Add(phraseBox);
        Controls.Add(hintLabel);
        Controls.Add(cancel);
        Controls.Add(confirm);
        Shown += delegate { FlipperTheme.DarkTitleBar(Handle); phraseBox.Focus(); };
    }
}

public static class FlipperTheme
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void DarkTitleBar(IntPtr handle)
    {
        try
        {
            int enabled = 1;
            if (DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int)) != 0)
            {
                DwmSetWindowAttribute(handle, 19, ref enabled, sizeof(int));
            }
        }
        catch { }
    }
}
'@ -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' -ErrorAction Stop
    if (-not ('FlipperToggle' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public sealed class FlipperToggle : Panel
{
    private bool isZero = false;
    private Image imgOne;
    private Image imgZero;
    private Color trackColor = Color.FromArgb(40, 40, 40);
    private Color thumbColor = Color.FromArgb(255, 140, 0);

    public bool IsZero { get { return isZero; } set { if (isZero == value) return; isZero = value; Invalidate(); } }
    public Image ImgOne { get { return imgOne; } set { imgOne = value; Invalidate(); } }
    public Image ImgZero { get { return imgZero; } set { imgZero = value; Invalidate(); } }

    public event EventHandler Toggled;

    public FlipperToggle()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
        Height = 36;
        Width = 120;
    }

    protected override void OnClick(EventArgs e)
    {
        base.OnClick(e);
        isZero = !isZero;
        Invalidate();
        EventHandler h = Toggled;
        if (h != null) h(this, EventArgs.Empty);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        int w = Width, h = Height;
        int r = h / 2;
        // track
        using (GraphicsPath track = RoundedRect(new Rectangle(0, 0, w - 1, h - 1), r))
        using (SolidBrush br = new SolidBrush(trackColor))
        using (Pen pen = new Pen(Color.FromArgb(60, 60, 60), 1f))
        {
            e.Graphics.FillPath(br, track);
            e.Graphics.DrawPath(pen, track);
        }
        // thumb
        int thumbW = h - 4;
        int thumbX = isZero ? (w - thumbW - 2) : 2;
        Rectangle thumbRect = new Rectangle(thumbX, 2, thumbW, h - 4);
        using (GraphicsPath thumb = RoundedRect(thumbRect, (h - 4) / 2))
        using (SolidBrush br = new SolidBrush(thumbColor))
        {
            e.Graphics.FillPath(br, thumb);
        }
        // image
        Image img = isZero ? imgZero : imgOne;
        if (img != null)
        {
            int imgSize = h - 10;
            int imgX = isZero ? (w - thumbW - 2 + (thumbW - imgSize) / 2) : (2 + (thumbW - imgSize) / 2);
            int imgY = (h - imgSize) / 2;
            e.Graphics.DrawImage(img, imgX, imgY, imgSize, imgSize);
        }
    }

    private static GraphicsPath RoundedRect(Rectangle rect, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        if (d > rect.Height) d = rect.Height;
        if (d > rect.Width) d = rect.Width;
        if (d < 2) d = 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
'@ -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' -ErrorAction Stop
    }
    if (-not ('FlipperProgressBar' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public sealed class FlipperProgressBar : Panel
{
    private int value = 0;
    private int maximum = 100;
    private Color fillColor = Color.FromArgb(255, 140, 0);
    private Color trackColor = Color.FromArgb(36, 36, 36);
    private bool marquee = false;
    private int marqueeOffset = 0;

    public int Value { get { return value; } set { this.value = Math.Max(0, Math.Min(maximum, value)); Invalidate(); } }
    public int Maximum { get { return maximum; } set { maximum = Math.Max(1, value); Invalidate(); } }
    public Color FillColor { get { return fillColor; } set { fillColor = value; Invalidate(); } }
    public Color TrackColor { get { return trackColor; } set { trackColor = value; Invalidate(); } }
    public bool Marquee { get { return marquee; } set { marquee = value; Invalidate(); } }
    public int MarqueeOffset { get { return marqueeOffset; } set { marqueeOffset = value; Invalidate(); } }

    public FlipperProgressBar()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = trackColor;
        Height = 14;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath path = RoundedRect(rect, 7))
        using (SolidBrush brush = new SolidBrush(trackColor))
        {
            e.Graphics.FillPath(brush, path);
        }
        if (marquee)
        {
            int blockW = Math.Max(20, Width / 5);
            int x = marqueeOffset % (Width + blockW) - blockW;
            Rectangle fillRect = new Rectangle(x, 0, blockW, Height);
            using (GraphicsPath path = RoundedRect(fillRect, 7))
            using (SolidBrush brush = new SolidBrush(fillColor))
            {
                e.Graphics.FillPath(brush, path);
            }
        }
        else
        {
            int fillWidth = maximum > 0 ? (int)((double)value / maximum * (Width - 1)) : 0;
            if (fillWidth > 0)
            {
                Rectangle fillRect = new Rectangle(0, 0, fillWidth, Height);
                using (GraphicsPath path = RoundedRect(fillRect, 7))
                using (SolidBrush brush = new SolidBrush(fillColor))
                {
                    e.Graphics.FillPath(brush, path);
                }
            }
        }
    }

    private static GraphicsPath RoundedRect(Rectangle rect, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        if (d > rect.Height) { d = rect.Height; }
        if (d > rect.Width) { d = rect.Width; }
        if (d < 2) { d = 2; }
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
'@ -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' -ErrorAction Stop
    }
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
    param([string]$State, [string]$Detail, [string]$Color)
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    $script:UiStatusTitle.Text = $State
    $script:UiStatusDetail.Text = $Detail
    $script:UiStatusDot.ForeColor = Get-UiColor $Color
}

function Refresh-UiStatus {
    if (-not $script:UiForm -or $script:UiForm.IsDisposed -or $script:UiBusy) { return }
    $snapshot = Get-UiSnapshot
    $script:UiEndpointApp.Text = "Flipper OS      port $($snapshot.AppPort)"
    $script:UiEndpointShelf.Text = "File Manager    port $($snapshot.ShelfPort)"
    if ($snapshot.Real) {
        if ($snapshot.Shelf) {
            Set-UiStatus 'REAL OS RUNNING' 'The real Flipper OS and the File Manager are running.' $script:UiColor.Success
        } else {
            Set-UiStatus 'REAL OS RUNNING' 'The real Flipper OS is running. The File Manager is starting or unavailable.' $script:UiColor.Blue
        }
    } elseif ($snapshot.Preview) {
        Set-UiStatus 'PREVIEW RUNNING' 'The FlipCTL preview is running in the background.' $script:UiColor.Success
    } else {
        Set-UiStatus 'STOPPED' 'No services are running. Choose an action to begin.' $script:UiColor.Faint
    }
    if ($script:UiMode -eq 'zero') { Refresh-ZeroUiStatus }
}

function Set-UiBusyAppearance {
    param([bool]$Busy)
    foreach ($card in $script:UiCards) { $card.Enabled = -not $Busy }
    if ($script:UiZeroButtons) { foreach ($zb in $script:UiZeroButtons) { $zb.Enabled = -not $Busy } }
    $script:UiBackupButton.Enabled = -not $Busy
    $script:UiRefreshButton.Enabled = -not $Busy
    $script:UiProgress.Visible = $Busy
    if ($Busy) { try { $script:UiProgress.Marquee = $true } catch { } } else { try { $script:UiProgress.Marquee = $false; $script:UiProgress.Value = 100 } catch { } }
    if ($Busy) { try { $script:UiProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee; $script:UiProgress.MarqueeAnimationSpeed = 30 } catch { } } else { try { $script:UiProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous; $script:UiProgress.Value = 100 } catch { } }
    if ($script:UiCancelButton) { $script:UiCancelButton.Visible = $Busy }
    if ($Busy) {
        try { $script:UiProgress.Value = 0 } catch { }
        $script:UiActivityState.Text = 'Working'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Warning
        $script:UiProgressDoneAt = $null
    } else {
        try { $script:UiProgress.Value = 100 } catch { }
        $script:UiActivityState.Text = 'Ready'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Faint
        $script:UiProgressDoneAt = Get-Date
    }
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
        $text = [IO.File]::ReadAllText($script:UiLogPath, [Text.Encoding]::UTF8)
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
        [string]$Accent,
        [bool]$CaseSensitive
    )
    return [FlipperConfirmDialog]::Confirm(
        $script:UiForm, $Title, $Heading, $Body, $Phrase,
        $ConfirmText, (Get-UiColor $Accent), $CaseSensitive)
}

function Show-UiMessage {
    param(
        [string]$Text,
        [string]$Title = 'Flipper One Demo',
        [string]$Kind = 'Information'
    )
    $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($Kind -eq 'Warning') { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
    if ($Kind -eq 'Error') { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
    [void][System.Windows.Forms.MessageBox]::Show($script:UiForm, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

function Start-UiAction {
    param([string]$Action)
    if ($script:UiBusy) { return }

    if ($Action -eq 'backup') {
        Open-UiBackup
        return
    }
    if ($Action -eq 'exit') {
        $script:UiForm.Close()
        return
    }

    $title = switch ($Action) {
        'preview'   { 'Starting the FlipCTL preview' }
        'real'      { 'Starting the real Flipper OS' }
        'files'     { 'Starting Flipper OS and File Manager' }
        'stop'      { 'Stopping everything' }
        'log'       { 'Loading the server log' }
        'uninstall' { 'Uninstalling Flipper One Demo' }
        'reinstall' { 'Reinstalling Flipper One Demo' }
        'reset'     { 'Resetting the Flipper OS' }
        'zero-install' { 'Installing the Flipper Zero emulator' }
        'zero-run'     { 'Running the Flipper Zero emulator' }
        'zero-stop'    { 'Stopping the Flipper Zero emulator' }
        'zero-show'    { 'Opening the Flipper Zero display' }
        'zero-reset'   { 'Resetting the Flipper Zero flash' }
        default     { 'Working' }
    }

    if ($Action -eq 'uninstall') {
        $body = "This removes the private Linux environment (FlipperOne), all downloaded files, the portable emulator, and the Start menu shortcuts." +
                "`n`nYour File Manager files are copied to the PC file backup first."
        $ok = Confirm-UiAction -Title 'Uninstall Flipper One Demo' -Heading 'Remove this helper?' `
            -Body $body -Phrase 'YES' -ConfirmText 'Uninstall' -Accent $script:UiColor.Danger -CaseSensitive $false
        if (-not $ok) {
            $script:UiActivityState.Text = 'Cancelled'
            $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Faint
            Add-UiLogMessage 'Uninstall cancelled. Nothing was changed.'
            return
        }
    }
    if ($Action -eq 'reinstall') {
        $body = "This removes the helper and its downloads, downloads a fresh copy, and restores the PC file backup." +
                "`n`nThis needs an internet connection and several GB of free space. It can take several minutes."
        $ok = Confirm-UiAction -Title 'Reinstall Flipper One Demo' -Heading 'Download a fresh setup?' `
            -Body $body -Phrase 'YES' -ConfirmText 'Reinstall' -Accent $script:UiColor.Orange -CaseSensitive $false
        if (-not $ok) {
            $script:UiActivityState.Text = 'Cancelled'
            $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Faint
            Add-UiLogMessage 'Reinstall cancelled. Nothing was changed.'
            return
        }
    }
    if ($Action -eq 'reset') {
        $body = "This deletes the real Flipper OS image with all apps, settings and files inside it." +
                "`nIt also deletes the PC file backup in %LOCALAPPDATA%\FlipperOneDemoFiles." +
                "`n`nThe Windows helper, its downloads and the FlipCTL preview are kept."
        $ok = Confirm-UiAction -Title 'Reset Flipper OS' -Heading 'Factory reset the Flipper OS?' `
            -Body $body -Phrase 'RESET' -ConfirmText 'Reset Flipper OS' -Accent $script:UiColor.Danger -CaseSensitive $true
        if (-not $ok) {
            $script:UiActivityState.Text = 'Cancelled'
            $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Faint
            Add-UiLogMessage 'Factory reset cancelled. Nothing was changed.'
            return
        }
    }

    if (-not (Test-Path -LiteralPath $script:UiBat)) {
        Show-UiMessage 'The helper copy for this window is missing. Close the app and start it again.' 'Flipper One Demo' 'Error'
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
    Set-UiStatus 'WORKING' $title $script:UiColor.Warning
    $script:UiActivityState.Text = $title

    try {
        $script:UiProcess = Start-Process -FilePath $wrapper -WorkingDirectory $script:UiWork -WindowStyle Hidden -PassThru
    } catch {
        $script:UiBusy = $false
        $script:UiProcess = $null
        $script:UiLogPath = $null
        Set-UiBusyAppearance $false
        Refresh-UiStatus
        Show-UiMessage ("The action could not be started.`n`n" + $_.Exception.Message) 'Flipper One Demo' 'Error'
    }
}

function Complete-UiAction {
    if (-not $script:UiProcess) { return }
    Update-UiLog
        try { if ($script:UiProgress.Marquee) { $script:UiProgress.MarqueeOffset = $script:UiProgress.MarqueeOffset + 8 } } catch { }
    $code = 0
    try { $code = $script:UiProcess.ExitCode } catch { }
    try { $script:UiProcess.Dispose() } catch { }
    $script:UiProcess = $null
    $action = $script:UiAction
    $script:UiBusy = $false
    $script:UiLogPath = $null
    $script:UiLogChars = 0
    Set-UiBusyAppearance $false
    if ($action -eq 'zero-install') { $script:ZeroInstalled = $null }
    Refresh-UiStatus

    $needsRestart = $script:UiLogText -match 'UI-EVENT:RESTART_REQUIRED'
    $hasWarning = $script:UiLogText -match '(?m)^\s*(!!|XX)\s'

    if ($needsRestart) {
        Show-UiMessage "Windows needs one restart to finish enabling WSL.`n`nAfter you sign in again, the helper continues automatically. If it does not, start the app again." 'Restart Windows' 'Information'
        $script:UiForm.Close()
        return
    }
    if ($code -ne 0) {
        $script:UiActivityState.Text = 'Needs attention'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Danger
        Show-UiMessage "The action did not finish (exit code $code).`n`nSee the activity log for details." 'Flipper One Demo' 'Error'
    } elseif ($action -eq 'uninstall') {
        $script:UiActivityState.Text = 'Uninstalled'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Muted
        Show-UiMessage "Flipper One Demo has been removed from this PC.`n`nThis window stays open so you can reinstall or close it." 'Uninstall finished' 'Information'
    } elseif ($action -eq 'reset') {
        $script:UiActivityState.Text = 'Reset finished'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Danger
        Show-UiMessage "The Flipper OS has been reset to factory state.`n`nThe next start creates a fresh Flipper. Apps, settings and files inside it are gone." 'Factory reset finished' 'Information'
    } elseif ($action -eq 'zero-install') {
        $script:UiActivityState.Text = 'Emulator installed'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Success
        Show-UiMessage "The Flipper Zero emulator is installed.`n`nChoose Official, Momentum or a custom firmware file, then click Run Emulator." 'Flipper Zero' 'Information'
    } elseif ($action -eq 'zero-run') {
        $script:UiActivityState.Text = 'Emulator running'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Success
    } elseif ($action -eq 'zero-stop') {
        $script:UiActivityState.Text = 'Emulator stopped'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Muted
    } elseif ($action -eq 'zero-reset') {
        $script:UiActivityState.Text = 'Flash reset'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Muted
    } elseif ($hasWarning) {
        $script:UiActivityState.Text = 'Finished with warnings'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Warning
    } else {
        $script:UiActivityState.Text = 'Finished'
        $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Success
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
        if ($action -eq 'zero-install') {
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
    $script:UiActivityState.Text = 'Cancelled'
    $script:UiActivityState.ForeColor = Get-UiColor $script:UiColor.Warning
    Add-UiLogMessage 'Action cancelled.'
    Refresh-UiStatus
}

function Update-Ui {
    if (-not $script:UiForm -or $script:UiForm.IsDisposed) { return }
    if ($script:UiBusy -and $script:UiProcess) {
        Update-UiLog
        try { if ($script:UiProgress.Marquee) { $script:UiProgress.MarqueeOffset = $script:UiProgress.MarqueeOffset + 8 } } catch { }
        try {
            if ($script:UiProgress.Value -lt 90) {
                $script:UiProgress.Value = [Math]::Min(90, $script:UiProgress.Value + 2)
            }
        } catch { }
        $exited = $false
        try { $exited = $script:UiProcess.HasExited } catch { $exited = $false }
        if ($exited) { Complete-UiAction }
    }
    if (-not $script:UiBusy) {
        if ($script:UiProgressDoneAt -and ((Get-Date) - $script:UiProgressDoneAt).TotalSeconds -ge 2) {
            try { $script:UiProgress.Value = 0 } catch { }
            $script:UiProgressDoneAt = $null
        }
        if (((Get-Date) - $script:UiLastStatus).TotalSeconds -ge 5) {
            Refresh-UiStatus
            $script:UiLastStatus = Get-Date
        }
    }
}

function New-UiActionCard {
    param(
        [string]$Action,
        [string]$Title,
        [string]$Description,
        [int]$Glyph,
        [string]$Accent
    )
    $card = New-Object FlipperActionCard($Action, $Title, $Description, ([string][char]$Glyph), (Get-UiColor $Accent))
    $card.Dock = [System.Windows.Forms.DockStyle]::Fill
    $card.add_ActionClicked({
        param($sender, $eventArgs)
        Start-UiAction ([FlipperActionCard]$sender).ActionKey
    })
    [void]$script:UiCards.Add($card)
    return $card
}

function New-UiRowStyle {
    param([System.Windows.Forms.SizeType]$Type, [single]$Value)
    return New-Object -TypeName System.Windows.Forms.RowStyle -ArgumentList @($Type, $Value)
}

function New-UiColumnStyle {
    param([System.Windows.Forms.SizeType]$Type, [single]$Value)
    return New-Object -TypeName System.Windows.Forms.ColumnStyle -ArgumentList @($Type, $Value)
}

function Add-UiBoxBorder {
    param($Panel)
    $Panel.Add_Paint({
        param($sender, $eventArgs)
        $pen = New-Object System.Drawing.Pen((Get-UiColor '#333333'), 1)
        try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1) }
        finally { $pen.Dispose() }
    })
}

function Apply-UiTheme {
    if ($script:UiTheme -eq 'zero') {
        $c = $script:UiColorZero
    } else {
        $c = $script:UiColorOne
    }
    $script:UiColor = $c
    if ($script:UiForm -and -not $script:UiForm.IsDisposed) {
        $script:UiForm.BackColor = Get-UiColor $c.Background
    }
}

function Switch-UiPage {
    if ($script:UiMode -eq 'zero') {
        try { $mainLayout.Controls.Remove($script:UiOnePage) } catch { }
        if (-not $mainLayout.Controls.Contains($script:UiZeroPage)) { $mainLayout.Controls.Add($script:UiZeroPage, 0, 1) }
        $script:UiZeroPage.Visible = $true
        $script:UiZeroPage.BringToFront()
    } else {
        try { $mainLayout.Controls.Remove($script:UiZeroPage) } catch { }
        if (-not $mainLayout.Controls.Contains($script:UiOnePage)) { $mainLayout.Controls.Add($script:UiOnePage, 0, 1) }
        $script:UiOnePage.Visible = $true
        $script:UiOnePage.BringToFront()
    }
}

# ---------------------------------------------------------------------------
# Flipper Zero emulator
# ---------------------------------------------------------------------------
$script:ZeroInstalled      = $null
$script:ZeroRunPidFile     = Join-Path $Root 'zero-run.pid'
$script:ZeroViewerPidFile  = Join-Path $Root 'zero-viewer.pid'

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
    try {
        $check = & wsl.exe -d FlipperOne -- bash -c "test -x ~/flipper-zero-emulator/tools/renode/renode && test -f ~/flipper-zero-emulator/run.sh && echo YES || echo NO" 2>&1
        $script:ZeroInstalled = ($check -match 'YES')
    } catch {
        $script:ZeroInstalled = $false
    }
    return [bool]$script:ZeroInstalled
}

function Refresh-ZeroUiStatus {
    if (-not $script:UiZeroStatus) { return }
    $installed = Test-ZeroInstalled
    $running = Test-ZeroRunning
    if (-not $installed) {
        $script:UiZeroStatus.Text = 'Status: not installed - click Install Emulator'
        return
    }
    if ($running) {
        if ((Read-ZeroPid $script:ZeroViewerPidFile) -gt 0) {
            $script:UiZeroStatus.Text = 'Status: running - display open'
        } else {
            $script:UiZeroStatus.Text = 'Status: running - display closed (Open Display)'
        }
    } else {
        $script:UiZeroStatus.Text = 'Status: installed - ready'
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
    'Return' = 'Ok'; 'Space' = 'Ok'
    'Back' = 'Back'; 'Escape' = 'Back'
}

$script:client = $null
$script:stream = $null
$script:writer = $null
$script:connected = $false
$script:lastConnect = [DateTime]::MinValue

function Connect-Monitor {
    if ($script:connected) { return }
    if (((Get-Date) - $script:lastConnect).TotalSeconds -lt 2) { return }
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
}

$form = New-Object System.Windows.Forms.Form
try { $form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance).SetValue($form, $true, $null) } catch { }
$form.Text = 'Flipper Zero Emulator'
$form.ClientSize = New-Object System.Drawing.Size(560, 400)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 16)
$form.KeyPreview = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

$screen = New-Object System.Windows.Forms.Panel
$screen.SetBounds(24, 24, 512, 256)
try { $screen.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance).SetValue($screen, $true, $null) } catch { }
$screen.BackColor = [System.Drawing.Color]::Black
$screen.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($screen)

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.SetBounds(24, 292, 512, 22)
$script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
$script:statusLabel.Text = 'Waiting for Renode...'
$form.Controls.Add($script:statusLabel)

$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.SetBounds(24, 286, 512, 108)
$btnPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 16)
$form.Controls.Add($btnPanel)

$script:pressedKeys = New-Object System.Collections.Generic.HashSet[string]

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
    $b.add_MouseDown({ param($s, $e) Send-Button $s.Tag $true })
    $b.add_MouseUp({ param($s, $e) Send-Button $s.Tag $false })
    $b.add_MouseLeave({ param($s, $e) Send-Button $s.Tag $false })
    $btnPanel.Controls.Add($b)
}

$hint = New-Object System.Windows.Forms.Label
$hint.SetBounds(24, 286 + 108 - 20, 512, 18)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$hint.Text = 'Q = quit'
$form.Controls.Add($hint)

$script:fbBitmap = New-Object System.Drawing.Bitmap(128, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$script:lastBytes = $null
$script:fbExists = $false

function Update-Frame {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FbPath)
    } catch { return }
    if ($bytes.Length -lt 8192) { return }
    if ($script:lastBytes -and $bytes.Length -eq $script:lastBytes.Length) {
        $same = $true
        for ($i = 0; $i -lt 8192; $i++) { if ($bytes[$i] -ne $script:lastBytes[$i]) { $same = $false; break } }
        if ($same) { return }
    }
    $script:lastBytes = $bytes
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, 128, 64)
        $bmpData = $script:fbBitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $pixels = New-Object int[] 8192
            for ($i = 0; $i -lt 8192; $i++) {
                if ($bytes[$i] -ne 0) { $pixels[$i] = [int]0xFFFF8C00 } else { $pixels[$i] = [int]0xFF000000 }
            }
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
    if ($script:pressedKeys.Contains($keyStr)) { $e.Handled = $true; return }
    [void]$script:pressedKeys.Add($keyStr)
    $name = $keyMap[$keyStr]
    if ($name) { Send-Button $name $true; $e.Handled = $true }
})
$form.add_KeyUp({
    param($sender, $e)
    $keyStr = [string]$e.KeyCode
    [void]$script:pressedKeys.Remove($keyStr)
    $name = $keyMap[$keyStr]
    if ($name) { Send-Button $name $false; $e.Handled = $true }
})
$form.add_Shown({ $form.Activate() })
$form.add_Deactivate({ $script:pressedKeys.Clear() })
$form.add_FormClosed({
    Write-Log 'viewer closed'
    if ($script:client) { try { $script:client.Close() } catch { } }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.add_Tick({
    Connect-Monitor
    Update-Frame
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

    $officialVersion = '1.5.1'
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
    Say 'Installing the Flipper Zero emulator (Renode) in WSL ...'
    Say 'This may take 15-30 minutes. Use Cancel to abort.'
    $sh = Join-Path $env:TEMP 'install-zero.sh'
    $lines = @(
        '#!/bin/bash',
        'set -e',
        'export DEBIAN_FRONTEND=noninteractive',
        'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi',
        'cd ~',
        'echo "=== Step 1: Clone repository ==="',
        'if [ ! -d flipper-zero-emulator ]; then',
        '  git clone --depth 1 https://github.com/d4rks1d33/Flipper-Zero-Emulator.git flipper-zero-emulator',
        'else',
        '  echo "Repository already present."',
        'fi',
        'cd flipper-zero-emulator',
        'echo "=== Step 2: Install dependencies ==="',
        '$SUDO apt-get update -y',
        '$SUDO apt-get install -y dosfstools mtools python3 python3-pip',
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
    & wsl.exe -d FlipperOne -- bash $wslSh
    if ($LASTEXITCODE -ne 0) {
        Warn "Installation failed with exit code $LASTEXITCODE. Check the activity log."
        return $false
    }
    $null = Test-ZeroInstalled -Refresh
    Say 'Flipper Zero emulator installed successfully.'
    return $true
}


function Apply-UiTheme {
    if ($script:UiTheme -eq 'zero') { $c = $script:UiColorZero } else { $c = $script:UiColorOne }
    $script:UiColor = $c
    if ($script:UiForm -and -not $script:UiForm.IsDisposed) {
        $script:UiForm.BackColor = Get-UiColor $c.Background
        if ($script:UiForm.Controls.Count -gt 0) {
            $sh = $script:UiForm.Controls[0]
            if ($sh) { $sh.BackColor = Get-UiColor $c.Background }
        }
    }
    if ($script:UiSidebar) { $script:UiSidebar.BackColor = Get-UiColor $c.Sidebar }
    if ($script:UiStatusCard) { $script:UiStatusCard.BackColor = Get-UiColor $c.Card }
    if ($script:UiOnePage) { $script:UiOnePage.BackColor = Get-UiColor $c.Background }
    if ($script:UiZeroPage) { $script:UiZeroPage.BackColor = Get-UiColor $c.Background }
}

function Show-Ui {
    Initialize-UiTypes
    try {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    } catch { }
    try {
        Initialize-UiWorkspace
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("The app window could not be prepared.`n`n" + $_.Exception.Message,
            'Flipper One Demo', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $script:UiCards.Clear()
    $script:UiBusy = $false
    $script:UiProcess = $null
    $script:UiLogPath = $null
    $script:UiLogChars = 0
    $script:UiLogText = ''
    $script:UiAction = ''
    $script:UiLastStatus = [DateTime]::MinValue

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Flipper One Demo $Version"
    $form.ClientSize = New-Object System.Drawing.Size(1080, 660)
    $form.MinimumSize = New-Object System.Drawing.Size(920, 620)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = Get-UiColor $script:UiColor.Background
    $form.ForeColor = Get-UiColor $script:UiColor.Text
    $form.Font = New-UiFont -Size 9
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.KeyPreview = $true
    $form.Icon = [System.Drawing.SystemIcons]::Application
    $script:UiForm = $form

    $shell = New-Object System.Windows.Forms.TableLayoutPanel
    $shell.Dock = [System.Windows.Forms.DockStyle]::Fill
    $shell.ColumnCount = 2
    $shell.RowCount = 1
    $shell.Margin = New-Object System.Windows.Forms.Padding(0)
    $shell.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$shell.ColumnStyles.Add((New-UiColumnStyle -Type Absolute -Value 258))
    [void]$shell.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 100))
    $form.Controls.Add($shell)

    # Sidebar ---------------------------------------------------------------
    $side = New-Object System.Windows.Forms.Panel
    $script:UiSidebar = $side
    $side.Dock = [System.Windows.Forms.DockStyle]::Fill
    $side.BackColor = Get-UiColor $script:UiColor.Sidebar
    $side.Padding = New-Object System.Windows.Forms.Padding(22, 22, 22, 18)
    $shell.Controls.Add($side, 0, 0)

    $sideLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $sideLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $sideLayout.ColumnCount = 1
    $sideLayout.RowCount = 7
    $sideLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $sideLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 86))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 16))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 124))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 96))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Percent -Value 100))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 42))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 42))
    [void]$sideLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 56))
    $side.Controls.Add($sideLayout)

    $brand = New-Object System.Windows.Forms.Panel
    $brand.Dock = [System.Windows.Forms.DockStyle]::Fill
    $brand.Margin = New-Object System.Windows.Forms.Padding(0)
    $brand.BackColor = Get-UiColor $script:UiColor.Sidebar
    $script:UiToggle = New-Object FlipperToggle
    $script:UiToggle.SetBounds(0, 0, 120, 36)
    try {
        $ms = New-Object System.IO.MemoryStream
        $b = [Convert]::FromBase64String($script:UiImgOne)
        $ms.Write($b, 0, $b.Length); $ms.Position = 0
        $script:UiToggle.ImgOne = [System.Drawing.Image]::FromStream($ms)
        $ms.Dispose()
    } catch { }
    try {
        $ms = New-Object System.IO.MemoryStream
        $b = [Convert]::FromBase64String($script:UiImgZero)
        $ms.Write($b, 0, $b.Length); $ms.Position = 0
        $script:UiToggle.ImgZero = [System.Drawing.Image]::FromStream($ms)
        $ms.Dispose()
    } catch { }
    $script:UiToggle.add_Toggled({
        if ($script:UiToggle.IsZero) {
            $script:UiTheme = 'zero'
            $script:UiMode = 'zero'
            $lblVersion.Text = "ZERO EMULATOR"
            $lblTagline.Text = 'Flipper Zero Emulator'
        } else {
            $script:UiTheme = 'one'
            $script:UiMode = 'one'
            $lblVersion.Text = ("DEMO " + $Version)
            $lblTagline.Text = 'Unofficial community helper'
        }
        Apply-UiTheme
        Switch-UiPage
        Refresh-UiStatus
    })
    $brand.Controls.Add($script:UiToggle)
    $lblVersion = New-UiLabel -Text ("DEMO " + $Version) -Size 9 -Color $script:UiColor.Accent -Style ([System.Drawing.FontStyle]::Bold)
    $lblVersion.SetBounds(0, 44, 214, 18)
    $lblTagline = New-UiLabel -Text 'Unofficial community helper' -Size 8.4 -Color $script:UiColor.Muted
    $lblTagline.SetBounds(0, 63, 214, 18)
    $brand.Controls.Add($lblVersion)
    $brand.Controls.Add($lblTagline)
    $sideLayout.Controls.Add($brand, 0, 0)

    $divider = New-Object System.Windows.Forms.Panel
    $divider.Dock = [System.Windows.Forms.DockStyle]::Fill
    $divider.Margin = New-Object System.Windows.Forms.Padding(0, 7, 0, 8)
    $divider.BackColor = Get-UiColor $script:UiColor.Sidebar
    $dividerLine = New-Object System.Windows.Forms.Panel
    $dividerLine.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $dividerLine.Height = 1
    $dividerLine.BackColor = Get-UiColor $script:UiColor.Border
    $divider.Controls.Add($dividerLine)
    $sideLayout.Controls.Add($divider, 0, 1)

    $statusCard = New-Object System.Windows.Forms.Panel
    $script:UiStatusCard = $statusCard
    $statusCard.Dock = [System.Windows.Forms.DockStyle]::Fill
    $statusCard.Margin = New-Object System.Windows.Forms.Padding(0)
    $statusCard.BackColor = Get-UiColor $script:UiColor.Card
    Add-UiBoxBorder $statusCard
    $script:UiStatusDot = New-UiLabel -Text ([string][char]0x25CF) -Size 15 -Color $script:UiColor.Faint -Family 'Segoe UI Symbol'
    $script:UiStatusDot.SetBounds(14, 10, 22, 24)
    $script:UiStatusTitle = New-UiLabel -Text 'STOPPED' -Size 10.5 -Color $script:UiColor.Text -Style ([System.Drawing.FontStyle]::Bold)
    $script:UiStatusTitle.SetBounds(40, 12, 174, 22)
    $script:UiStatusDetail = New-UiLabel -Text 'Checking the current state...' -Size 8.4 -Color $script:UiColor.Muted
    $script:UiStatusDetail.SetBounds(40, 38, 176, 68)
    $lblLive = New-UiLabel -Text 'Updated automatically' -Size 7.5 -Color $script:UiColor.Faint
    $lblLive.SetBounds(14, 102, 210, 14)
    $statusCard.Controls.Add($script:UiStatusDot)
    $statusCard.Controls.Add($script:UiStatusTitle)
    $statusCard.Controls.Add($script:UiStatusDetail)
    $statusCard.Controls.Add($lblLive)
    $sideLayout.Controls.Add($statusCard, 0, 2)

    $endpoints = New-Object System.Windows.Forms.Panel
    $endpoints.Dock = [System.Windows.Forms.DockStyle]::Fill
    $endpoints.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $endpoints.BackColor = Get-UiColor $script:UiColor.Sidebar
    $lblServices = New-UiLabel -Text 'LOCAL SERVICES' -Size 7.8 -Color $script:UiColor.Faint -Style ([System.Drawing.FontStyle]::Bold)
    $lblServices.SetBounds(0, 0, 210, 16)
    $script:UiEndpointApp = New-UiLabel -Text 'Flipper OS      port 8899' -Size 8.4 -Color $script:UiColor.Muted
    $script:UiEndpointApp.SetBounds(0, 22, 214, 18)
    $script:UiEndpointShelf = New-UiLabel -Text 'File Manager    port 8898' -Size 8.4 -Color $script:UiColor.Muted
    $script:UiEndpointShelf.SetBounds(0, 42, 214, 18)
    $lblLocal = New-UiLabel -Text 'Everything stays on this PC.' -Size 7.8 -Color $script:UiColor.Faint
    $lblLocal.SetBounds(0, 64, 214, 18)
    $endpoints.Controls.Add($lblServices)
    $endpoints.Controls.Add($script:UiEndpointApp)
    $endpoints.Controls.Add($script:UiEndpointShelf)
    $endpoints.Controls.Add($lblLocal)
    $sideLayout.Controls.Add($endpoints, 0, 3)

    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.Dock = [System.Windows.Forms.DockStyle]::Fill
    $spacer.BackColor = Get-UiColor $script:UiColor.Sidebar
    $sideLayout.Controls.Add($spacer, 0, 4)

    $script:UiBackupButton = New-UiButton -Text 'Open PC File Backup' -Height 36
    $script:UiBackupButton.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiBackupButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $script:UiBackupButton.add_Click({ Open-UiBackup })
    $sideLayout.Controls.Add($script:UiBackupButton, 0, 5)

    $script:UiPowerMeterButton = New-UiButton -Text 'Open Power Meter Demo' -Height 36
    $script:UiPowerMeterButton.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiPowerMeterButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $script:UiPowerMeterButton.Font = New-UiFont -Size 8.5
    $script:UiPowerMeterButton.BackColor = Get-UiColor '#1C1C1C'
    $script:UiPowerMeterButton.ForeColor = Get-UiColor $script:UiColor.Muted
    $script:UiPowerMeterButton.FlatAppearance.BorderSize = 1
    $script:UiPowerMeterButton.FlatAppearance.BorderColor = Get-UiColor $script:UiColor.Border
    $script:UiPowerMeterButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#2A2A2A'
    $script:UiPowerMeterButton.add_Click({ Start-Process 'https://dev.repetren.com/power_meter_demo/'; Add-UiLogMessage 'Opened the Power Meter demo in your browser.' })
    $sideLayout.Controls.Add($script:UiPowerMeterButton, 0, 6)

    $footer = New-UiLabel -Text "Unofficial community helper`nNot affiliated with Flipper Devices." -Size 7.6 -Color $script:UiColor.Faint
    $footer.Dock = [System.Windows.Forms.DockStyle]::Fill
    $footer.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $sideLayout.Controls.Add($footer, 0, 7)

    # Main area -------------------------------------------------------------
    $main = New-Object System.Windows.Forms.Panel
    $main.Dock = [System.Windows.Forms.DockStyle]::Fill
    $main.BackColor = Get-UiColor $script:UiColor.Background
    $main.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
    $shell.Controls.Add($main, 1, 0)

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 3
    $mainLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$mainLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 58))
    [void]$mainLayout.RowStyles.Add((New-UiRowStyle -Type Percent -Value 100))
    [void]$mainLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 152))
    $main.Controls.Add($mainLayout)

    $header = New-Object System.Windows.Forms.TableLayoutPanel
    $header.Dock = [System.Windows.Forms.DockStyle]::Fill
    $header.ColumnCount = 2
    $header.RowCount = 1
    [void]$header.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 58))
    $header.Margin = New-Object System.Windows.Forms.Padding(0)
    $header.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$header.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 100))
    [void]$header.ColumnStyles.Add((New-UiColumnStyle -Type Absolute -Value 88))
    $mainLayout.Controls.Add($header, 0, 0)

    $headerText = New-Object System.Windows.Forms.Panel
    $headerText.Dock = [System.Windows.Forms.DockStyle]::Fill
    $headerText.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $headerText.BackColor = Get-UiColor $script:UiColor.Background
    $lblActions = New-UiLabel -Text 'Actions' -Size 18 -Color '#F2F2F2' -Style ([System.Drawing.FontStyle]::Regular) -Family 'Segoe UI Semibold'
    $lblActions.SetBounds(0, 0, 500, 32)
    $lblActionsSub = New-UiLabel -Text 'Choose what you want to do. Long operations keep running and report in the activity log.' -Size 8.6 -Color $script:UiColor.Muted
    $lblActionsSub.SetBounds(0, 32, 700, 20)
    $headerText.Controls.Add($lblActions)
    $headerText.Controls.Add($lblActionsSub)
    $header.Controls.Add($headerText, 0, 0)

    $script:UiRefreshButton = New-Object System.Windows.Forms.Label
    $script:UiRefreshButton.Text = 'Refresh'
    $script:UiRefreshButton.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiRefreshButton.Margin = New-Object System.Windows.Forms.Padding(4, 16, 8, 16)
    $script:UiRefreshButton.Font = New-UiFont -Size 8.5
    $script:UiRefreshButton.BackColor = Get-UiColor '#1C1C1C'
    $script:UiRefreshButton.ForeColor = Get-UiColor $script:UiColor.Muted
    $script:UiRefreshButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:UiRefreshButton.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:UiRefreshButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:UiRefreshButton.AutoSize = $false
    $script:UiRefreshButton.AutoEllipsis = $true
    $script:UiRefreshButton.add_MouseEnter({ $script:UiRefreshButton.BackColor = Get-UiColor '#2A2A2A' })
    $script:UiRefreshButton.add_MouseLeave({ $script:UiRefreshButton.BackColor = Get-UiColor '#1C1C1C' })
    $script:UiRefreshButton.add_Click({
        if ($script:UiMode -eq 'zero') { $script:ZeroInstalled = $null }
        Refresh-UiStatus
        $script:UiLastStatus = Get-Date
        Add-UiLogMessage 'Status refreshed.'
    })
    $header.Controls.Add($script:UiRefreshButton, 1, 0)

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.ColumnCount = 3
    $grid.RowCount = 6
    $grid.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    $grid.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$grid.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 33.333))
    [void]$grid.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 33.333))
    [void]$grid.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 33.333))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 22))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Percent -Value 33.333))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 22))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Percent -Value 33.333))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 22))
    [void]$grid.RowStyles.Add((New-UiRowStyle -Type Percent -Value 33.333))
    $mainLayout.Controls.Add($grid, 0, 1)

    $script:UiOnePage = $grid
    $script:UiZeroPage = New-Object System.Windows.Forms.Panel
    $script:UiZeroPage.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiZeroPage.Visible = $false
    $script:UiZeroPage.BackColor = Get-UiColor $script:UiColor.Background
    $mainLayout.Controls.Add($script:UiZeroPage, 0, 1)

    $zeroLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $zeroLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroLayout.ColumnCount = 1
    $zeroLayout.RowCount = 9
    $zeroLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $zeroLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 36))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 34))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 44))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 40))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 44))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 44))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 44))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 44))
    [void]$zeroLayout.RowStyles.Add((New-UiRowStyle -Type Percent -Value 100))
    $script:UiZeroPage.Controls.Add($zeroLayout)
    $script:UiZeroButtons = New-Object System.Collections.ArrayList

    $zeroTitle = New-UiLabel -Text 'FLIPPER ZERO EMULATOR' -Size 14 -Color $script:UiColor.Accent -Style ([System.Drawing.FontStyle]::Bold)
    $zeroTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $zeroTitle.Margin = New-Object System.Windows.Forms.Padding(6, 8, 6, 4)
    $zeroLayout.Controls.Add($zeroTitle, 0, 0)

    $script:UiZeroStatus = New-UiLabel -Text 'Status: not installed' -Size 10 -Color $script:UiColor.Text
    $script:UiZeroStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiZeroStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:UiZeroStatus.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroLayout.Controls.Add($script:UiZeroStatus, 0, 1)

    $zeroInstallBtn = New-UiButton -Text 'Install Emulator' -Height 34
    $zeroInstallBtn.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroInstallBtn.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroInstallBtn.BackColor = Get-UiColor $script:UiColor.Card
    $zeroInstallBtn.ForeColor = Get-UiColor $script:UiColor.Text
    $zeroInstallBtn.add_Click({
        $script:UiZeroStatus.Text = 'Installing... (15-30 min)'
        Start-UiAction 'zero-install'
    })
    [void]$script:UiZeroButtons.Add($zeroInstallBtn)
    $zeroLayout.Controls.Add($zeroInstallBtn, 0, 2)

    $fwPanel = New-Object System.Windows.Forms.Panel
    $fwPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $fwPanel.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $fwLabel = New-UiLabel -Text 'Firmware:' -Size 9 -Color $script:UiColor.Muted
    $fwLabel.SetBounds(0, 4, 80, 20)
    $fwBranch = New-Object System.Windows.Forms.ComboBox
    $fwBranch.SetBounds(80, 4, 120, 24)
    $fwBranch.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $fwBranch.Items.AddRange(@('Official', 'Momentum', 'Custom file'))
    $fwBranch.SelectedIndex = 0
    $script:UiZeroFirmwareCombo = $fwBranch
    $fwBranch.add_SelectedIndexChanged({
        $sel = [string]$script:UiZeroFirmwareCombo.SelectedItem
        switch ($sel) {
            'Momentum'    { $script:ZeroBranch = 'momentum' }
            'Custom file' { $script:ZeroBranch = 'custom' }
            default       { $script:ZeroBranch = 'official' }
        }
        if ($sel -ne 'Custom file') { $script:ZeroCustomFirmware = '' }
        Refresh-ZeroUiStatus
    })
    $fwBrowse = New-UiButton -Text 'Browse...' -Height 24 -Width 80
    $fwBrowse.SetBounds(210, 4, 80, 24)
    $fwBrowse.add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Firmware files (*.tgz;*.bin)|*.tgz;*.bin|All files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:ZeroCustomFirmware = $dlg.FileName
            $script:UiZeroStatus.Text = 'Custom: ' + [IO.Path]::GetFileName($dlg.FileName)
        }
    })
    [void]$script:UiZeroButtons.Add($fwBrowse)
    $fwPanel.Controls.Add($fwLabel)
    $fwPanel.Controls.Add($fwBranch)
    $fwPanel.Controls.Add($fwBrowse)
    $zeroLayout.Controls.Add($fwPanel, 0, 3)

    $zeroRunBtn = New-UiButton -Text 'Run Emulator' -Height 34
    $zeroRunBtn.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroRunBtn.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroRunBtn.BackColor = Get-UiColor $script:UiColor.Accent
    $zeroRunBtn.ForeColor = Get-UiColor '#FFFFFF'
    $zeroRunBtn.add_Click({
        Start-UiAction 'zero-run'
    })
    [void]$script:UiZeroButtons.Add($zeroRunBtn)
    $zeroLayout.Controls.Add($zeroRunBtn, 0, 4)

    $zeroShowBtn = New-UiButton -Text 'Open Display' -Height 34
    $zeroShowBtn.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroShowBtn.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroShowBtn.BackColor = Get-UiColor $script:UiColor.Card
    $zeroShowBtn.ForeColor = Get-UiColor $script:UiColor.Text
    $zeroShowBtn.add_Click({
        Start-UiAction 'zero-show'
    })
    [void]$script:UiZeroButtons.Add($zeroShowBtn)
    $zeroLayout.Controls.Add($zeroShowBtn, 0, 5)

    $zeroStopBtn = New-UiButton -Text 'Stop Emulator' -Height 34
    $zeroStopBtn.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroStopBtn.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroStopBtn.BackColor = Get-UiColor $script:UiColor.Warning
    $zeroStopBtn.ForeColor = Get-UiColor '#FFFFFF'
    $zeroStopBtn.add_Click({
        Start-UiAction 'zero-stop'
    })
    [void]$script:UiZeroButtons.Add($zeroStopBtn)
    $zeroLayout.Controls.Add($zeroStopBtn, 0, 6)

    $zeroResetBtn = New-UiButton -Text 'Reset Flash' -Height 34
    $zeroResetBtn.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroResetBtn.Margin = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
    $zeroResetBtn.BackColor = Get-UiColor $script:UiColor.Card
    $zeroResetBtn.ForeColor = Get-UiColor $script:UiColor.Text
    $zeroResetBtn.add_Click({
        Start-UiAction 'zero-reset'
    })
    [void]$script:UiZeroButtons.Add($zeroResetBtn)
    $zeroLayout.Controls.Add($zeroResetBtn, 0, 7)

    $zeroHelp = New-UiLabel -Text 'In the display: arrows = D-pad, Enter = OK, Backspace = Back, Q = close.' -Size 8.4 -Color $script:UiColor.Faint
    $zeroHelp.Dock = [System.Windows.Forms.DockStyle]::Fill
    $zeroHelp.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $zeroHelp.Margin = New-Object System.Windows.Forms.Padding(7, 8, 7, 4)
    $zeroLayout.Controls.Add($zeroHelp, 0, 8)

    $groupStart = New-UiLabel -Text 'START' -Size 7.8 -Color $script:UiColor.Faint -Style ([System.Drawing.FontStyle]::Bold)
    $groupStart.Margin = New-Object System.Windows.Forms.Padding(7, 4, 7, 0)
    $grid.Controls.Add($groupStart, 0, 0)
    $grid.SetColumnSpan($groupStart, 3)

    $cPreview = New-UiActionCard -Action 'preview' -Title 'FlipCTL Preview' -Description 'Fast, stable browser preview. No QEMU required.' -Glyph 0x25B6 -Accent $script:UiColor.Accent
    $cReal = New-UiActionCard -Action 'real' -Title 'Real Flipper OS' -Description 'Boot the experimental operating system in QEMU.' -Glyph 0x25C6 -Accent $script:UiColor.Blue
    $cFiles = New-UiActionCard -Action 'files' -Title 'OS + File Manager' -Description 'Start both and open them in two browser tabs.' -Glyph 0x25A4 -Accent $script:UiColor.Success
    $grid.Controls.Add($cPreview, 0, 1)
    $grid.Controls.Add($cReal, 1, 1)
    $grid.Controls.Add($cFiles, 2, 1)

    $groupServices = New-UiLabel -Text 'SERVICES' -Size 7.8 -Color $script:UiColor.Faint -Style ([System.Drawing.FontStyle]::Bold)
    $groupServices.Margin = New-Object System.Windows.Forms.Padding(7, 4, 7, 0)
    $grid.Controls.Add($groupServices, 0, 2)
    $grid.SetColumnSpan($groupServices, 3)

    $cStop = New-UiActionCard -Action 'stop' -Title 'Stop Everything' -Description 'Stop the preview, hidden browser and QEMU.' -Glyph 0x25A0 -Accent $script:UiColor.Warning
    $cLog = New-UiActionCard -Action 'log' -Title 'Show Server Log' -Description 'Show the latest preview server messages here.' -Glyph 0x2261 -Accent $script:UiColor.Muted
    $cExit = New-UiActionCard -Action 'exit' -Title 'Exit App' -Description 'Close this window. Running services stay active.' -Glyph 0x2715 -Accent $script:UiColor.Faint
    $grid.Controls.Add($cStop, 0, 3)
    $grid.Controls.Add($cLog, 1, 3)
    $grid.Controls.Add($cExit, 2, 3)

    $groupMaint = New-UiLabel -Text 'MAINTENANCE' -Size 7.8 -Color $script:UiColor.Faint -Style ([System.Drawing.FontStyle]::Bold)
    $groupMaint.Margin = New-Object System.Windows.Forms.Padding(7, 4, 7, 0)
    $grid.Controls.Add($groupMaint, 0, 4)
    $grid.SetColumnSpan($groupMaint, 3)

    $cUninstall = New-UiActionCard -Action 'uninstall' -Title 'Uninstall' -Description 'Remove the helper, Linux environment and downloads.' -Glyph 0x2212 -Accent $script:UiColor.Danger
    $cReinstall = New-UiActionCard -Action 'reinstall' -Title 'Reinstall' -Description 'Remove everything, download fresh and restore files.' -Glyph 0x21BB -Accent $script:UiColor.Orange
    $cReset = New-UiActionCard -Action 'reset' -Title 'Reset Flipper OS' -Description 'Delete the OS image and PC backup. Start fresh next time.' -Glyph 0x21BA -Accent $script:UiColor.Danger
    $grid.Controls.Add($cUninstall, 0, 5)
    $grid.Controls.Add($cReinstall, 1, 5)
    $grid.Controls.Add($cReset, 2, 5)

    # Activity --------------------------------------------------------------
    $activity = New-Object System.Windows.Forms.Panel
    $activity.Dock = [System.Windows.Forms.DockStyle]::Fill
    $activity.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $activity.Padding = New-Object System.Windows.Forms.Padding(12, 9, 12, 9)
    $activity.BackColor = Get-UiColor $script:UiColor.Card
    Add-UiBoxBorder $activity
    $mainLayout.Controls.Add($activity, 0, 2)

    $activityLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $activityLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $activityLayout.ColumnCount = 1
    $activityLayout.RowCount = 3
    $activityLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $activityLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$activityLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 24))
    [void]$activityLayout.RowStyles.Add((New-UiRowStyle -Type Percent -Value 100))
    [void]$activityLayout.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 14))
    $activity.Controls.Add($activityLayout)

    $activityHeader = New-Object System.Windows.Forms.TableLayoutPanel
    $activityHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
    $activityHeader.ColumnCount = 4
    $activityHeader.RowCount = 1
    [void]$header.RowStyles.Add((New-UiRowStyle -Type Absolute -Value 58))
    $activityHeader.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$activityHeader.ColumnStyles.Add((New-UiColumnStyle -Type Percent -Value 100))
    [void]$activityHeader.ColumnStyles.Add((New-UiColumnStyle -Type Absolute -Value 190))
    [void]$activityHeader.ColumnStyles.Add((New-UiColumnStyle -Type Absolute -Value 62))
    [void]$activityHeader.ColumnStyles.Add((New-UiColumnStyle -Type Absolute -Value 62))
    $activityLayout.Controls.Add($activityHeader, 0, 0)

    $lblActivity = New-UiLabel -Text 'ACTIVITY' -Size 7.8 -Color $script:UiColor.Faint -Style ([System.Drawing.FontStyle]::Bold)
    $lblActivity.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lblActivity.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $activityHeader.Controls.Add($lblActivity, 0, 0)

    $script:UiActivityState = New-UiLabel -Text 'Ready' -Size 8.2 -Color $script:UiColor.Faint
    $script:UiActivityState.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiActivityState.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $script:UiActivityState.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $activityHeader.Controls.Add($script:UiActivityState, 1, 0)

    $clearButton = New-UiButton -Text 'Clear' -Height 22
    $clearButton.Dock = [System.Windows.Forms.DockStyle]::Fill
    $clearButton.Margin = New-Object System.Windows.Forms.Padding(2, 1, 0, 1)
    $clearButton.Font = New-UiFont -Size 8
    $clearButton.add_Click({ $script:UiLogBox.Clear() })
    $activityHeader.Controls.Add($clearButton, 2, 0)

    $script:UiCancelButton = New-UiButton -Text 'Cancel' -Height 22
    $script:UiCancelButton.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiCancelButton.Margin = New-Object System.Windows.Forms.Padding(2, 1, 0, 1)
    $script:UiCancelButton.Font = New-UiFont -Size 8
    $script:UiCancelButton.Visible = $false
    $script:UiCancelButton.add_Click({ Stop-UiAction })
    $activityHeader.Controls.Add($script:UiCancelButton, 3, 0)

    $script:UiLogBox = New-Object System.Windows.Forms.TextBox
    $script:UiLogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiLogBox.Multiline = $true
    $script:UiLogBox.ReadOnly = $true
    $script:UiLogBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:UiLogBox.BackColor = Get-UiColor '#0A0A0A'
    $script:UiLogBox.ForeColor = Get-UiColor '#D0D0D0'
    $script:UiLogBox.Font = New-UiFont -Size 8.5 -Family 'Consolas'
    $script:UiLogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $script:UiLogBox.WordWrap = $false
    $script:UiLogBox.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)
    $activityLayout.Controls.Add($script:UiLogBox, 0, 1)

    $script:UiProgress = New-Object FlipperProgressBar
    $script:UiProgress.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:UiProgress.Maximum = 100
    $script:UiProgress.Value = 0
    $script:UiProgress.FillColor = Get-UiColor $script:UiColor.Accent
    $script:UiProgress.TrackColor = Get-UiColor '#242424'
    $script:UiProgress.Visible = $false
    $script:UiProgress.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)
    $activityLayout.Controls.Add($script:UiProgress, 0, 2)

    # Window events ---------------------------------------------------------
    $form.add_Shown({
        [FlipperTheme]::DarkTitleBar($script:UiForm.Handle)
        Refresh-UiStatus
        $script:UiLastStatus = Get-Date
        Add-UiLogMessage "Flipper One Demo $Version is ready."
    })
    $form.add_FormClosing({
        param($sender, $eventArgs)
        if ($script:UiBusy) {
            $answer = [System.Windows.Forms.MessageBox]::Show($sender,
                "An operation is still running.`n`nClose this window anyway? The operation will continue in the background.",
                'Close Flipper One Demo',
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
            Refresh-UiStatus
            $script:UiLastStatus = Get-Date
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
if ($cmd -eq 'ui-zero-install') { Install-ZeroEmulator; exit 0 }
if ($cmd -eq 'ui-zero-run') {
    $selFile = Join-Path $Root 'zero-selection.json'
    if (Test-Path -LiteralPath $selFile) {
        try {
            $sel = Get-Content -LiteralPath $selFile -Raw | ConvertFrom-Json
            if ($sel.branch) { $script:ZeroBranch = [string]$sel.branch }
            if ($sel.custom) { $script:ZeroCustomFirmware = [string]$sel.custom }
        } catch { }
    }
    $null = Run-ZeroEmulator
    exit 0
}
if ($cmd -eq 'ui-zero-show') { $null = Start-ZeroViewer; exit 0 }
if ($cmd -eq 'ui-zero-stop') { Stop-ZeroEmulator; exit 0 }
if ($cmd -eq 'ui-zero-reset') { Reset-ZeroFlash; exit 0 }
if ($cmd -eq 'powermeter' -or $cmd -eq 'demo' -or $cmd -eq 'power') { Start-Process 'https://dev.repetren.com/power_meter_demo/'; Write-Host 'Opened the Power Meter demo in your browser.'; exit 0 }

Write-Host ''
Write-Host "=== Flipper One Demo v$Version ===" -ForegroundColor Yellow
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
