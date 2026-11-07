# Flipper Emulator for Windows

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D6)
![Requires](https://img.shields.io/badge/requires-WSL%202-blue)
![Status](https://img.shields.io/badge/status-unofficial-orange)
![Version](https://img.shields.io/badge/public_release-8.0-brightgreen)

Try the **Flipper One** user interface and emulate the **Flipper Zero** on any Windows PC - no device, no extra hardware, no manual setup.

A single double-click on `FlipperEmulator 8.0.bat` (current public release) downloads everything it needs, sets up an isolated Linux environment, and lets you choose between three Flipper One modes and a separate **Flipper Zero emulator**:

- **FlipCTL preview** - the fast, stable test UI from the Flipper One image. Hardware features are simulated.
- **Real Flipper OS** - the actual Flipper OS kernel and initramfs, booted in QEMU (aarch64) on your PC. Experimental.
- **Flipper OS + File Manager** - starts both and opens the OS and the file/app shelf in two browser tabs. Upload files from Windows, install your own Flipper app bundles and launch them under **Apps**.
- **Flipper Zero emulator** - runs the real Flipper Zero firmware (STM32WB55) in Renode with an on-screen display and keyboard/mouse buttons. It runs at real Flipper Zero speed (since 7.11), so a normal click is a short press and only a held key is a long press.

> **Stable helper, experimental emulation:** 8.0 is the current public release of this Windows helper. It brings a completely redesigned app window (dark Flipper One look, light Flipper Zero look, a one-click **Uninstall Everything**) and keeps everything from 7.11 (real-time Flipper Zero emulation) and 6.6 (persistent menu, app shelf, factory reset, option 3 that never restarts a running OS). 7.11, 6.6 and 5.3 remain available as earlier releases. The real-OS mode itself remains experimental because QEMU emulates hardware the image was not built for.

> **Disclaimer:** This is an unofficial community project. It is **not** affiliated with or endorsed by Flipper Devices. This repository contains no Flipper software - the helper only downloads publicly available components from their official sources.

---

## Table of Contents

- [What is this?](#what-is-this)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [File Manager](#file-manager)
- [Unofficial App Shelf](#unofficial-app-shelf)
- [Real Flipper OS Mode](#real-flipper-os-mode)
- [Flipper Zero Emulator](#flipper-zero-emulator)
- [Internet Access (NAT)](#internet-access-nat)
- [How It Works](#how-it-works)
- [What Gets Installed](#what-gets-installed)
- [Uninstalling](#uninstalling)
- [Reinstalling](#reinstalling)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Security Note](#security-note)
- [Version 8.0 (current public release)](#version-80-current-public-release)
- [Version 7.11 (previous public release)](#version-711-previous-public-release)
- [Version 6.6 (previous public release)](#version-66-previous-public-release)
- [Version 5.3 (previous public release)](#version-53-previous-public-release)
- [Version 5.2 (previous development build)](#version-52-previous-development-build)
- [Version 5.1 (previous development build)](#version-51-previous-development-build)
- [Version 5.0 (development build)](#version-50-development-build)
- [Version 4.1 (previous public release)](#version-41-previous-public-release)
- [Version 4.0 (previous test build)](#version-40-previous-test-build)
- [Version 3.0 (test build)](#version-30-test-build)
- [Version 2.3 (previous stable release)](#version-23-previous-stable-release)
- [Contributing](#contributing)
- [License](#license)

---

## What is this?

The Flipper One software is under active development and is, by design, meant to run on the actual device. This project makes it possible to get a first impression of the interface - and to test it - directly on a Windows PC.

The helper provides three ways to use it:

### FlipCTL preview

The preview runs the **FlipCTL test version** of the Flipper One UI. It is rendered in your browser and talks to a local test server, so everything works without real hardware. Features that depend on physical components (Wi-Fi, modem, battery, GPIO, etc.) are **dummies**.

### Real Flipper OS

The real-OS mode boots the actual Flipper OS kernel and initramfs from the public Flipper One image inside QEMU. The image targets a Rockchip RK3576 (ARM) board, so the hardware is fully emulated on your PC. This is useful for testing the real system, but it is slower than real hardware and cannot use your PC's Wi-Fi, modem, battery or GPIO.

### Flipper OS + File Manager

The File Manager adds a small, separate web page for **your own files**. It runs inside the real Flipper OS and is available while the real OS is running. Upload files from Windows, organize them in folders, and open them in Flipper apps from `/home/user/Files`. The same page is also an **unofficial app shelf**: put a Flipper app bundle there, choose **Install**, and it appears in the real OS under **Apps**.

In 5.3, menu option **3** starts the Flipper OS (if it is not already running) and the File Manager, then opens both in two browser tabs. If the OS is already running, only the File Manager tab is added and the OS is not restarted. Menu option **8** performs a factory reset of the real Flipper OS. The helper also keeps a copy of your files on your PC, so they survive an uninstall and are restored automatically after a reinstall.

---

## Requirements

| Requirement | Details |
|---|---|
| **OS** | 64-bit Windows 10 or Windows 11 |
| **WSL 2** | Windows Subsystem for Linux 2. The helper installs it if it is missing. |
| **Virtualization** | Must be enabled in the BIOS/UEFI for WSL 2. |
| **Browser** | Microsoft Edge or Google Chrome recommended. All modes open in your default browser; one of Edge/Chrome is additionally used as a hidden device renderer for the preview. |
| **Disk space** | Plan for about 12 GB free during setup. The finished installation uses about 8-9 GB. |
| **Internet** | Required for setup and reinstall. Normal use works offline. |
| **RAM** | 8 GB recommended for the real OS. The preview runs on less. |
| **Administrator rights** | The app and QEMU do not need administrator rights. Windows may ask once for permission to enable WSL. |

---

## Quick Start

1. **Download** `FlipperEmulator 8.0.bat` from the `Public Releases` folder. This is the current public release. Earlier public releases remain available there.
2. **Double-click** the file. You can keep it anywhere; the helper installs its own copy.
3. **Wait** while the first-time setup runs. It downloads several GB and may take a while.
4. When the menu appears, choose **1** for the FlipCTL preview, **2** for the real Flipper OS, or **3** for Flipper OS + File Manager. Pressing **Enter** starts the preview.
5. Your browser opens automatically. Done.

> **First time using WSL?** If WSL is not set up yet, the helper starts its installation (you will be asked to confirm one administrator prompt). Windows may require a restart. The helper registers a one-time auto-resume, so setup continues after you sign in again. If it does not continue automatically, simply double-click the file again.

After the first successful setup, the helper stores a copy at `%LOCALAPPDATA%\FlipperOneDemo\Flipper-One-Demo.bat` and creates Start menu shortcuts.

---

## Usage

After setup, running the file shows a simple menu:

```
[1] FlipCTL preview  (fast, stable)
[2] Real Flipper OS  (experimental, QEMU emulation)
[3] Flipper OS + File Manager  (opens both in two browser tabs)
[4] Stop everything
[5] Uninstall everything
[6] Reinstall
[7] Show server log
[8] Reset Flipper OS  (factory reset, deletes apps and files)
[9] Exit
  Status: stopped
```

| Option | What it does |
|---|---|
| **1** | Starts the FlipCTL preview server and opens the UI in your browser. |
| **2** | Boots the real Flipper OS in QEMU and opens it in your browser. If the OS is already running, it is reused and not restarted. |
| **3** | Starts the Flipper OS if needed, starts the File Manager, and opens both in two browser tabs. If the OS is already running, only the File Manager tab is added. |
| **4** | Stops the preview server, the hidden device browser and QEMU. The menu stays open, so you can start something else afterwards. |
| **5** | Copies the latest File Manager files to the PC backup, then removes the private Linux environment, all downloaded files, portable QEMU, settings and shortcuts. The PC backup is kept. |
| **6** | Performs a full uninstall and a fresh automatic reinstall. It restores the real Flipper OS if you used it before; otherwise the FlipCTL preview. File Manager files are restored automatically. |
| **7** | Shows the last lines of the preview server log. |
| **8** | Factory reset of the real Flipper OS. Asks you to type `RESET`, then stops everything, deletes the OS image (all apps, settings and files inside it) and the PC file backup. The helper, its downloads and the FlipCTL preview are kept. The next real-OS start creates a fresh Flipper. |
| **9** | Closes the menu. A running preview or real OS keeps running in the background. |

Press **Enter** to accept the default (**1**, FlipCTL preview), or type a number and confirm.

After every action the menu returns, so you can stop everything and then start another mode without running the `.bat` again. The console stays open until you choose **9**.

> **Updating from an older version:** the first start of the real OS adds the File Manager to the existing image. This is a one-time step of about 10 seconds and keeps your apps and files. If you open option 3 in a session that was already running before the update, the helper offers one restart.

### Start menu shortcuts

On the first successful setup, these shortcuts are created under **Flipper One Demo** in the Start menu:

- **Flipper One Demo** - opens the menu.
- **Start FlipCTL Preview** - starts option 1 directly.
- **Start Real Flipper OS** - starts option 2 directly.
- **Open File Manager** - opens option 3 directly: starts the Flipper OS if needed and opens the OS and the File Manager in two browser tabs.
- **Open PC File Backup** - opens `%LOCALAPPDATA%\FlipperOneDemoFiles` in Explorer.
- **Stop Flipper One** - stops everything.

### Command-line arguments

The helper also accepts these command-line arguments:

| Argument | Action |
|---|---|
| `start` | Start the FlipCTL preview and open the browser. |
| `stop` | Stop the preview, the hidden browser and QEMU. |
| `real` or `realos` | Start the real Flipper OS. |
| `files` | Start the real OS if needed, start the File Manager, and open both in two browser tabs. |
| `backup` | Open the PC file backup folder in Explorer. |
| `log` | Show the last lines of the preview server log. |
| `uninstall` | Remove everything without asking for confirmation. The latest File Manager files are backed up first. |
| `reset` | Factory reset of the real Flipper OS. Deletes the OS image and the PC file backup after you type `RESET`. |
| `qemu` | Download and prepare the portable QEMU emulator. |
| `install` | Set up or repair the installation without starting the app. |
| `reinstall` | Full uninstall and fresh setup, then restore the real Flipper OS if it was used before; otherwise the FlipCTL preview. Files are restored too. |
| `resume` | Internal one-time resume after a required Windows restart. |

`start`, `real` and `files` start what is needed and return immediately; the app keeps running in the background. Use **[4] Stop everything** or the `stop` argument to stop it. `stop`, `log`, `uninstall`, `qemu` and `install` run without prompts; `reinstall` asks for the YES confirmation and `reset` asks for `RESET`.

Example:

```bat
FlipperEmulator 8.0.bat start
FlipperEmulator 8.0.bat real
FlipperEmulator 8.0.bat files
FlipperEmulator 8.0.bat reset
FlipperEmulator 8.0.bat stop
```

### Stopping the app

The preview and the real OS keep running in the background, even if you close the console window. To stop them:

- Choose **[4] Stop everything** in the menu. The menu stays open, so you can start another mode right away.
- Use the **Stop Flipper One** Start menu shortcut.
- Run the file again with the `stop` argument.

Closing the console window or choosing **[9] Exit** does not stop a running instance. Stopping the app does not delete the PC file backup. The factory reset in option 8 does delete that backup.

---

## File Manager

The File Manager is a small file shelf for `/home/user/Files` inside the real Flipper OS. It is meant for everyday use: copy a file from Windows, then open it in an app or the App Manager without setting up SSH, SCP or a network share.

### Opening it

- Choose **[3] Flipper OS + File Manager** in the menu.
- Or use the **Open File Manager** Start menu shortcut.
- Or run `FlipperEmulator 5.3.bat files`.

Option 3 starts whatever is missing and opens the OS and the File Manager in two browser tabs. If the real OS is already running, it is reused and only the File Manager tab is added; QEMU is not restarted. The File Manager and the real OS share the same machine, so both are available at the same time.

### What you can do

- **Upload** files with the button or by dragging them onto the page.
- **Download** files back to Windows.
- **Create folders**, **rename** and **delete** files or folders.
- Use **Unicode names**, spaces and normal Windows file names.
- **Install app bundles** from the folder into Flipper OS and launch them under **Apps** (see [Unofficial App Shelf](#unofficial-app-shelf)).
- Open the **App Manager** from the link in the page header.

Files are stored in `/home/user/Files` inside the Flipper OS. Apps can open them there. The File Manager cannot leave that folder: paths are checked on the guest side.

### PC backup and restore

The helper keeps a copy of the folder on your PC:

```
%LOCALAPPDATA%\FlipperOneDemoFiles
```

- The copy is refreshed when the real OS starts and again before an uninstall.
- **Uninstall** (option 5) removes the emulator but keeps this folder.
- **Reinstall** (option 6) restores the folder into the fresh image, including subfolders, empty folders and Unicode names.
- The **Open PC File Backup** shortcut opens the folder in Explorer.
- If you no longer need the files, delete the folder manually.

The backup is a safety copy, not a live sync service: changes made while the real OS is running are copied to the PC at the next start or before an uninstall.

### Port and safety

The File Manager page uses `http://127.0.0.1:8898/` by default and the real OS uses `http://127.0.0.1:8899/`. If one of these ports is busy, the helper picks the next free local port and opens the correct address automatically. Both services listen on **localhost only**; nothing is exposed to your local network. The upload endpoint checks the target path, rejects traversal attempts and writes files atomically. The install endpoint validates the AppImage header and only writes into `/home/user/Apps`.

---

## Unofficial App Shelf

Version 5.3 keeps the File Manager as a small, unofficial app store for the real Flipper OS and adds a native test app to show what a real bundle looks like. The workflow is the same as for the preinstalled apps: put a bundle in, install it, open **Apps**.

The `TestApps` folder next to the helper contains two ready-made bundles:

- `native-hello-aarch64.fap.AppImage` - a native SDL2 program (not a browser page) with its own ARM64 CLI helper. Upload it, install it, and start **Native Hello** under **Apps**.
- `shelf-test-aarch64.fap.AppImage` - the earlier browser-based test bundle, kept for comparison.

### Install an app

1. Start the real Flipper OS (option **2**) or open the File Manager (option **3**).
2. Open `http://127.0.0.1:8898/`.
3. Upload your Flipper app bundle or drag it onto the page. The file stays in `/home/user/Files`.
4. Choose **Install** next to the file and confirm. The page shows an **Installed** badge when the copy exists in the OS.
5. Open the **App Manager** link, or open **Apps** on the Flipper OS panel. The new app is listed there and can be started.

**Reinstall** replaces the installed copy with the file from Files, for example after you uploaded a newer build. **Remove** deletes the installed copy from the OS; the file in Files is kept. Close a running app before removing it.

### What the shelf accepts

The shelf installs Flipper app bundles, not arbitrary Windows or Linux programs:

- The file must end in `.AppImage` (commonly `myapp-aarch64.fap.AppImage`).
- It must be a type-2 AppImage with an ELF header, built for **ARM64 / aarch64**.
- Inside the AppImage's squashfs, at its root, there must be an `app.toml` with at least a non-empty `wayland` command. That manifest is what makes it a Flipper app; flipctl reads it without running the bundle.
- Stock desktop AppImages usually have no `app.toml`. The shelf may accept their file format, but Flipper OS will ignore them under **Apps**.

The shelf checks the AppImage header before copying, so wrong-architecture and type-1 images are rejected with a message. A successful install copies the bundle to `/home/user/Apps`, sets it executable and leaves the source in `/home/user/Files`. flipctl finds bundles anywhere under `/home/user/Apps`; top-level bundles appear directly in **Apps**, while bundles in subfolders are grouped by that folder (for example the preinstalled **Games** folder with Doom).

To build a compatible bundle, use the Flipper OS app bundler (`tools/appimage/build.sh apps/<name>` in the Flipper OS source tree). It produces an AppImage with `app.toml` and `AppRun` at the squashfs root.

### Trust and limitations

An installed bundle runs as code inside the emulated Flipper OS. The header check only verifies the format, not that the app is safe or works. **Only install bundles you trust.**

- The shelf does not download apps from the internet; it only installs files you put into the File Manager.
- GNU/Linux binaries built for x86, `.deb` packages and plain scripts are not supported.
- Removing an app deletes only its bundle. The app's work data under `~/.local/share/flipctl/apps/<key>` and its extracted manifest cache under `~/.cache/flipctl/bundles/<key>` may remain inside the image.
- A full reinstall creates a fresh image. Installed bundles are not part of the PC file backup, so keep the `.AppImage` files in Files and install them again after a reinstall.
- The app must draw its own screen and be compatible with the Flipper OS UI stack; a generic desktop application only works if it was built for Flipper OS.

---

## Real Flipper OS Mode

The real-OS mode is experimental. It boots the actual Flipper OS kernel and initramfs from the public image, with the image's root filesystem mounted read-write.

- **Emulation:** QEMU `virt` machine with a Cortex-A72 CPU and TCG software emulation. No ARM hardware is required.
- **Internet:** automatic. The guest uses QEMU user-mode networking (NAT), receives `10.0.2.15` by DHCP and can reach the host at `10.0.2.2`, DNS at `10.0.2.3` and the internet. Nothing has to be configured, inside or outside the guest.
- **Memory/CPU:** The helper sizes QEMU to your PC (2-4 GB RAM, up to 4 vCPUs).
- **First start:** Usually 1-3 minutes. Slower PCs may take longer. The helper waits up to 7 minutes before showing a warning.
- **One-time setup:** On the first real-OS start, the helper adds the DHCP profile and, in 5.0 and later, the File Manager and app shelf service to the image. This takes about 20 seconds in total; keep the console window open until those steps have finished. If interrupted, the next start safely retries.
- **URL:** `http://127.0.0.1:8899/` by default. If port 8899 is busy, the helper picks the next free local port and opens it automatically.
- **Persistence:** The raw image is writable, so changes made inside the emulated OS persist until you reinstall, including apps installed from the shelf. Your File Manager files are also mirrored to the PC and restored after a reinstall.
- **Installed apps:** Apps installed in the image can be started from the Apps page or the in-OS App Manager. Doom, for example, starts and renders on the emulated panel. Starting a hosted app can take a few minutes under software emulation.
- **App rendering:** QEMU has no GPU, so hosted apps use SDL's software renderer and a software compositor. Apps that require a real GPU may still not work.
- **Hardware:** Wi-Fi, modem, battery, GPIO and other physical features are not available. Errors about missing hardware are expected.
- **QEMU source:** If a system QEMU is already installed, it is reused. Otherwise a portable QEMU is downloaded and unpacked under the app folder. No administrator rights are needed.

---

## Internet Access (NAT)

The real Flipper OS runs with internet access out of the box. QEMU provides user-mode networking (NAT), so no network bridge, no administrator rights and no Windows firewall rule are required.

| From the guest | Address | Meaning |
|---|---|---|
| Guest IP | `10.0.2.15` (DHCP) | Assigned automatically by QEMU |
| Gateway / host | `10.0.2.2` | The Windows PC that runs QEMU |
| DNS | `10.0.2.3` | QEMU's DNS forwarder |
| Internet | any | TCP/UDP and ICMP are forwarded through the host |

How it works:

- QEMU starts with `-netdev user,id=net0` and a `virtio-net` adapter with a fixed MAC address.
- The first time the real OS starts, the helper adds one small file to the image: `/etc/systemd/network/10-qemu-nat.network`. It matches only the `virtio_net` driver, so real Rockchip hardware is never affected. The file is written to a temporary name first and then renamed, so an interrupted write cannot leave a half-written profile.
- On every boot, `systemd-networkd` applies that profile, requests an address by DHCP and passes gateway and DNS to the system.
- The profile is stored in the image, so it survives reboots. A reinstall re-creates it automatically.
- The helper writes it only once. If the write fails or is interrupted, the image keeps its previous behaviour, the built-in DHCP fallback still works and the next start retries.

Notes:

- **Outbound only.** The guest can reach the internet and the Windows host. Incoming connections are not forwarded, except the UI and File Manager ports that the helper publishes on `127.0.0.1`.
- `10.0.2.2` is the **Windows host**, not the WSL distribution. WSL has its own virtual network behind Windows.
- Wi-Fi, modem and Bluetooth errors in the guest log are expected: that hardware does not exist in QEMU. They do not block the boot and do not affect internet access.
- The `stun.services.mozilla.com` messages in the flipctl log are harmless: that hostname no longer exists.

---

## Flipper Zero Emulator

Besides the Flipper One modes, the app has a **Flipper Zero** page that runs the real Flipper Zero firmware on an emulated STM32WB55 using [Renode](https://renode.io/) inside the same WSL environment. It builds on the community project [d4rks1d33/Flipper-Zero-Emulator](https://github.com/d4rks1d33/Flipper-Zero-Emulator), which the helper downloads at install time; this repository contains none of it.

**The Zero page works like a launcher:**

- **Status badge** - shows whether the emulator is installed (*Installed*, *Running* or *Not installed*).
- **Install Emulator / Reinstall Emulator** - one button: *Install* when the emulator is missing (about 15-30 minutes, first time only; the private Linux environment is created automatically if needed), *Reinstall* when it is already there.
- **Firmware selector** - *Official* (stock 1.5.1 plus its resources), *Momentum*, or *Custom file* (your own `.bin`, `.dfu` or update package, chosen with **Browse...**).
- **Start / Stop** - one button. **Start** prepares the firmware and the emulated SD card, starts Renode and opens the display window; while the emulator runs the same button becomes **Stop**.
- **Open Display** - reopens the display window if you closed it.
- **Reset Flash** - restores the bundled stock firmware in the emulated flash.
- **Exit App** - closes the window (top right, on both pages).

**Controls in the display window:** arrow keys or `W` `A` `S` `D` = D-pad, `Enter` or `Space` = OK, `Backspace` or `Esc` = Back, `Q` = close. The on-screen buttons work with the mouse. Tap for a short press, hold for a long press, exactly like the real device.

**Real-time speed (since 7.11):** the emulated firmware used to run its internal clock two to seven times faster than real time, so a normal click was read as a long press. The helper now applies a small, repeatable patch to the emulator before every start (the firmware is not modified). The firmware clock stays within about 2 % of real time, a press shorter than roughly 300 ms is a short press and a longer one is a long press.

**Limitations:** this is an emulation of the processor and basic peripherals. Radio (Sub-GHz, NFC, RFID, Bluetooth), infrared and USB are not emulated, and some apps that need them or a different firmware API will not run.

---

## How It Works

1. **WSL check** - verifies that WSL 2 is available and installs it if necessary. This is the only step that may ask for administrator permission and may require a restart.
2. **Private Linux environment** - imports an Ubuntu 24.04 base system as a dedicated WSL distribution named `FlipperOne`. Your existing WSL distributions are not touched.
3. **Image download and decompression** - downloads the public Flipper One image (about 2 GB compressed) and decompresses it to a raw image of about 6 GB with portable zstd. The compressed download is deleted afterwards; the raw image is kept because the real-OS mode needs it.
4. **Extraction** - mounts the image read-only inside the private WSL distribution and extracts the FlipCTL preview UI, the kernel and the initramfs.
5. **Preview setup** - installs Node.js inside the private environment, runs the FlipCTL test server on port 8899 and starts a hidden Edge/Chrome instance that identifies itself like the device browser.
6. **Real-OS image setup** - on the first real-OS start, mounts the image read-write once and adds:
   - a matching `systemd-networkd` DHCP profile for the QEMU network adapter;
   - the File Manager and app shelf service and page under `/usr/local/lib/flipper-one-demo`, enabled as `flipper-files-shelf.service`;
   - the folders `/home/user/Files` with a short README and `/home/user/Apps` for your own app bundles.
7. **Real-OS startup** - uses an existing system QEMU or prepares the portable QEMU. It then boots the extracted kernel and initramfs with the raw image, forwards the localhost ports to the guest and waits for the web UI.
8. **File backup and restore** - before starting QEMU, the helper exports `/home/user/Files` to `%LOCALAPPDATA%\FlipperOneDemoFiles` (only if the File Manager is already installed). Before an uninstall it exports again. After a fresh install it imports the PC copy.
9. **Browser** - opens the preview, the real OS or the File Manager in your normal browser. Everything runs locally; no cloud service is involved.

---

## What Gets Installed

| Component | Purpose | Source |
|---|---|---|
| Flipper One Linux image (about 2 GB compressed, about 6 GB raw) | Preview UI and real-OS filesystem | `dl-linux-images.flipp.dev` |
| Ubuntu 24.04 WSL base system (about 350 MB download) | Private Linux environment | `cloud-images.ubuntu.com` |
| Node.js 22.11.0 | Preview server | `nodejs.org` |
| zstd 1.5.7 | Decompress the Flipper One image | GitHub (`meta/zstd`) |
| 7-Zip 23.01 | Unpack the portable QEMU installer | `7-zip.org` |
| Portable QEMU (only if no system QEMU is found; about 200 MB download, about 1.2 GB unpacked) | Real-OS emulation | `qemu.weilnetz.de` |
| File Manager and app shelf service (about 50 KB, embedded in the helper) | Upload page, app install API and file API inside the real Flipper OS | Included in the `.bat` |
| WSL itself (only if it was missing) | Windows component | Microsoft |

Everything the helper manages is stored in:

- `%LOCALAPPDATA%\FlipperOneDemo` - app files, image, logs, tools and optionally QEMU
- `%LOCALAPPDATA%\FlipperOneDemoFiles` - your File Manager files (kept by the console uninstall, removed by Uninstall Everything)
- a private WSL distribution named `FlipperOne`
- Start menu shortcuts under **Flipper One Demo**

If QEMU is already installed system-wide, it is reused but not modified. Nothing else is installed outside these locations, apart from WSL itself if it was missing.

### Disk space

- Finished installation: about **8-9 GB** (about 6 GB image + about 2 GB WSL distribution, plus tools and optional portable QEMU).
- During setup: plan for about **12 GB free** because the compressed download, the raw image and the Linux environment exist at the same time.
- The PC file backup uses as much space as the files you upload.

---

## Uninstalling

**Uninstall Everything** (in the app window, on the Flipper One and on the Flipper Zero page) removes *everything* the helper has put on your PC so that all of the disk space is free again. Type **DELETE** to confirm. This does **not** keep a backup.

It removes:

- the private WSL distribution `FlipperOne`, including the Flipper Zero emulator and Renode
- the complete `%LOCALAPPDATA%\FlipperOneDemo` folder (Flipper OS image, portable QEMU, helper tools, downloads, logs, browser profile)
- `%LOCALAPPDATA%\FlipperOneDemoFiles` (your File Manager files and the PC backup)
- downloaded Flipper Zero firmwares and installer scripts in the Windows temp folder
- the Start menu shortcuts and the one-time auto-resume entry

It does **not** remove: other WSL distributions, WSL itself (a Windows feature), a system-wide QEMU installation, or the `.bat` file you downloaded.

The same is available on the command line with `FlipperEmulator 8.0.bat wipe`.

The console menu option **[5] Uninstall everything** (and the `uninstall` argument) still exists for the older, gentler removal: it first copies your File Manager files to `%LOCALAPPDATA%\FlipperOneDemoFiles` and keeps that backup folder.

If files remain, close all browser windows and try again; if the WSL distribution is busy, restart Windows and repeat. Afterwards starting any function simply installs it again.

---

## Reinstalling

Run the file and choose **[6] Reinstall**. Type **YES** to confirm.

A reinstall performs a complete uninstall followed by a fresh automatic setup. It needs an internet connection and the same free disk space as the first installation.

The helper remembers whether you actually used the real Flipper OS. After a reinstall it restores that mode automatically:

- real Flipper OS if you used it before
- FlipCTL preview otherwise

If you used the File Manager, its files are restored from `%LOCALAPPDATA%\FlipperOneDemoFiles` into the fresh image, including subfolders, empty folders and Unicode names. Installed app bundles are not restored automatically: keep the `.AppImage` files in Files and install them again from the shelf. You can switch modes at any time with **[1]** and **[2]**.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| **"WSL could not be installed"** | Allow the administrator prompt. If it still fails, open an administrator PowerShell and run `wsl --install --no-distribution`, then restart your PC. |
| **Setup stops after a restart** | Double-click the file again. The one-time auto-resume normally continues automatically, but a manual restart works too. |
| **"Import failed"** | Make sure virtualization is enabled in your BIOS/UEFI and that WSL 2 is available. |
| **"Loop devices are not available"** | Run `wsl --update` in PowerShell and try again. |
| **Download fails** | Check your internet connection and run the file again. Incomplete downloads are restarted automatically. |
| **Blank preview page or server not responding** | Choose **[7] Show server log**, or try **[6] Reinstall**. |
| **Port 8899 is busy** | Close the program using port 8899. The preview needs this port. The real-OS and File Manager modes choose the next free ports automatically. |
| **File Manager says it is not active** | This happens after updating from an older version in a session that was already running. Accept the offered restart, or stop and start the real OS again. Option 3 then opens normally. |
| **File Manager does not open** | Make sure the real OS is running or choose option 3, which starts it. Check `http://127.0.0.1:8898/api/status` in the browser. If the port is busy, the helper uses another port and prints the correct address. |
| **Upload fails or reports no space** | The Flipper OS image is full. Delete files you no longer need in the File Manager, or reinstall to get a fresh image. Your PC backup is kept. |
| **Files are missing after a reinstall** | Check `%LOCALAPPDATA%\FlipperOneDemoFiles`. The folder is restored automatically when the image gets the File Manager; if it is empty, the files were never exported (for example because the image was already removed manually). |
| **Real Flipper OS does not boot** | Wait up to 7 minutes. Check `%LOCALAPPDATA%\FlipperOneDemo\realos\serial.log` and `qemu.err.log`. The image is built for RK3576 hardware; emulation may not work on every PC. Try **[6] Reinstall**. |
| **An app does not appear in the real OS** | Wait a few minutes: software emulation is slow, and Doom in particular takes time to mount and start. Then try the app again from the Apps page or the in-OS App Manager. Apps that need a real GPU may not work. |
| **My installed app is not listed under Apps** | It must be a Flipper app bundle with `app.toml` at the squashfs root and built for ARM64. Stock desktop AppImages are ignored. Open **Apps** again to trigger a rescan. |
| **Install rejects my AppImage** | The shelf accepts only type-2 AppImages with an ARM64 ELF header. Rebuild the app for Flipper OS; an x86 build or a type-1 image cannot run in the emulator. |
| **Remove fails** | Close the app in the Flipper OS first, then choose **Remove** again. The installed bundle is locked while the app is running. |
| **An installed app does not start** | Not every app is compatible with the emulated UI stack. Check the app requirements and the Flipper OS log. Apps that need a real GPU may fail even though they are listed. |
| **No internet in the real OS** | Close and start the real OS again. On the first start, wait for the one-time network profile to finish (about 10 seconds) and keep the console window open. Inside the guest, `10.0.2.2` is the Windows host and `10.0.2.3` is DNS. If a reinstall also fails, include the last lines of `qemu.err.log` in an issue. |
| **Ping fails but websites load** | Windows may block QEMU's ICMP forwarding on some systems. TCP and DNS still work, so the guest has internet. Test with a browser or a normal download. |
| **QEMU download fails** | If a system QEMU is installed, it is used automatically. Otherwise check your connection and run `FlipperEmulator 5.3.bat qemu` to retry the portable download. |
| **No browser found** | Install Microsoft Edge or Google Chrome. The preview needs one of them for the hidden device renderer. |
| **Uninstall leaves files behind** | Close all browser windows and retry. If the private WSL distribution is busy, restart Windows and run uninstall again. |
| **Antivirus blocks a download** | The helper downloads large tools from official sources. Allow the files after checking them, then retry. |

If the problem persists, open an issue and include the output of **[7] Show server log**. For real-OS problems, also include the last lines of `serial.log` and `qemu.err.log`.

---

## Limitations

- The **FlipCTL preview** is a test/demo UI. There is no real hardware behind it; Wi-Fi, modem, battery and other hardware features are dummies.
- The **real Flipper OS** mode is experimental. It runs under QEMU software emulation, is slower than real hardware and cannot access your PC's hardware.
- The **File Manager** is only available while the real Flipper OS is running. It is not a general Windows file share or a live sync service.
- The **app shelf** installs only Flipper app bundles for ARM64 with an `app.toml`; it is not a general app store, does not download anything and does not verify that a bundle is safe.
- The real OS is built for a Rockchip RK3576 board. Some image versions may change the internal structure and require an update of this helper.
- The helper requires WSL 2 and virtualization. It is not available on systems where virtualization is disabled or unsupported.
- The real-OS image is writable. Changes persist locally until you reinstall. File Manager files are additionally mirrored to the PC, but installed app bundles are not.
- Internet access in the real OS is **outbound only** (QEMU user-mode NAT). The guest is not reachable from your local network.

---

## Security Note

The `.bat` file is plain text. It launches an embedded PowerShell script with `-ExecutionPolicy Bypass` for that one process only and downloads several large files.

- Downloads come from official sources: `dl-linux-images.flipp.dev`, `cloud-images.ubuntu.com`, `nodejs.org`, GitHub (`meta/zstd`), `7-zip.org` and `qemu.weilnetz.de`.
- The 7-Zip MSI is verified with SHA-256. QEMU checksums are verified when the mirror provides them.
- The preview server, the real-OS port forwarding and the File Manager listen on **localhost only**. The File Manager service runs as the unprivileged guest user `user` and writes only under `/home/user/Files` and `/home/user/Apps`.
- Installed app bundles run as code inside the emulated guest. The shelf verifies the AppImage format and architecture before installing, but that is not a safety or trust check. Only install bundles you trust.
- The helper does not collect telemetry or send data to a cloud service.

As with any script from the internet, **please read it before you run it**.

---

## Version 8.0 (current public release)

Version **8.0** redesigns the app window and adds a complete removal:

- **New name in the window:** "Flipper Emulator 8.0", because both the Flipper One and the Flipper Zero can now be emulated.
- **Device slider:** top left, with the Flipper One picture on the left and the Flipper Zero picture on the right (both embedded in the file, no extra files needed). Only the elements of the selected device are shown.
- **Dark and light theme:** the Flipper One side is dark grey and orange, the Flipper Zero side is white and orange. The window fades smoothly between them.
- **Flipper One page:** *Real Flipper OS* comes first, with a checkbox to open the File Manager together with the OS. Next to it are *FlipCTL Preview* and *Power Meter Demo*, followed by the Manage and Maintenance rows. The status card and the activity log are unchanged.
- **Flipper Zero page:** a launcher with an installed/not installed badge, **Install / Reinstall Emulator**, a firmware selector (Official, Momentum, Custom file), a **Start / Stop** button, **Open Display**, **Reset Flash** and **Exit App**.
- **Uninstall Everything:** one button on both pages that removes everything the helper installed (QEMU, the Flipper Zero emulator, firmwares, files and temporary data) and frees all of the disk space. Confirmed by typing `DELETE`.
- **Standalone Zero install:** the Flipper Zero emulator no longer needs the Flipper One setup first; the private Linux environment is created automatically.
- **Honest results:** starting or installing the Zero emulator now reports a failure as a failure.
- **Fixes:** the Cancel button works during long operations.

The data folder is still `%LOCALAPPDATA%\FlipperOneDemo`, so existing installations are recognised.

SHA-256 of `FlipperEmulator 8.0.bat`:

`8B12237F7FF54128133118ADE965BE420DD1F5109BFEF762A0595A50395830C7`

`FlipperEmulator 8.0.bat` is available in `Public Releases` and `DevBuilds`.

---

## Version 7.11 (previous public release)

Version **7.11** is a previous public release. It keeps everything from 6.6 and fixes the input timing of the Flipper Zero emulator:

- **Real-time Zero emulation:** the emulated firmware's clock now matches real time (measured ratio 1.00 over minutes, previously up to 7x too fast). Normal clicks are short presses, held keys are long presses, with the same ~300 ms threshold as the real Flipper Zero.
- **Emulator patch:** the helper applies a small, repeatable patch to the Renode emulator before each start. It makes the firmware use plain light sleep and connects and resets the idle timer correctly. The firmware itself is untouched, and the patch can run repeatedly without harm.
- **Reworked display window:** buttons are sent on key/mouse down and released as soon as you let go (50 ms minimum), key auto-repeat is ignored, and frame loading runs on a separate thread so it can no longer delay your input. Buttons are released if the window loses focus.
- **Removed:** the old speed workarounds from earlier development builds.

SHA-256 of `FlipperEmulator 7.11.bat`:

`235CB108BB25AEFD7F058168F51492C838ED36A9CE239C9EFD6481634680C0B5`

`FlipperEmulator 7.11.bat` is available in `Public Releases` and `DevBuilds`.

---
## Version 6.6 (previous public release)

Version **6.6** is a previous public release and is included in `Public Releases` and `DevBuilds`. It keeps every feature of 5.3 (persistent console menu, option 3 that opens the OS and File Manager without restarting a running OS, option 2 reuse, factory reset, app shelf, native test bundle) and adds a **Windows app** on top:

- **Graphical interface:** double-clicking the helper opens a WinForms window with a sidebar status card, nine action cards (Preview, Real Flipper OS, OS + File Manager, Stop, Uninstall, Reinstall, Show Server Log, Reset, Exit), a live activity log, a progress bar and typed confirmations (`YES` / case-sensitive `RESET`).
- **No console window:** the app starts hidden; long operations run in a background child process and report into the activity log.
- **Progress feedback:** each of the three start actions shows an approximate progress bar that fills while the operation runs, so long downloads and QEMU boots are visualised.
- **Corporate identity:** orange / grey / black colour scheme inspired by Flipper Devices (no logos).
- **Option 3 fixed:** when the Flipper OS is already running, the app reopens the OS tab instead of opening a duplicate File Manager tab; the File Manager address is shown without duplicating it.
- **Same command line:** all existing arguments (`start`, `real`, `files`, `stop`, `backup`, `log`, `uninstall`, `reinstall`, `reset`, `install`, `qemu`, `resume`) keep working; the console menu remains available via `menu`.
- **Everything from 5.3 remains:** persistent menu, option 3 reuse, option 2 reuse, factory reset, app shelf, native **Native Hello** test bundle.

SHA-256 of `FlipperEmulator 6.6.bat`:

`D7FC7CA9564896E781320C5AAAF304BDFB933E68EC24B4AD68DD5DA05FBCE59D`

`FlipperEmulator 6.6.bat` is available in `Public Releases` and `DevBuilds`.

---
## Version 5.3 (previous public release)

Version **5.3** is the current public release and is included in `Public Releases` and `DevBuilds`. It keeps the persistent menu, the app shelf and the native test app from 5.2 and adds a complete factory reset for the real Flipper OS:

- **Factory reset in the menu:** option **8** asks you to type `RESET`, then stops QEMU and the File Manager, deletes the real OS image (all apps, settings and files inside it) and the PC file backup. The Windows helper, its downloads and the FlipCTL preview are kept.
- **Fresh Flipper on the next start:** the next option 2 or 3 creates a new Flipper from the stock image. If the compressed stock image is no longer cached, the helper downloads it again, so the next start can take a few minutes.
- **Exit is now option 9:** because option 8 is the reset, the menu numbering changed. Actions 1-8 return to the menu; 9 closes it. A running preview or real OS keeps running in the background after 9.
- **Same command line:** `FlipperEmulator 5.3.bat reset` performs the same factory reset and asks for `RESET` before deleting anything.
- **Everything from 5.2 remains:** persistent menu, option 3 that opens the OS and File Manager without restarting a running OS, option 2 reuse, and the native **Native Hello** test bundle.

Verified before hand-off:

- the reset was tested with the real installation: the OS image and the PC file backup were deleted, the menu stayed usable, and **9 Exit** closed it
- the demo image and its backup were restored afterwards; the restored image boots with shelf version 5.3, keeps **Native Hello**, and `btrfs check --readonly` reports no errors
- the reset also passed in an isolated sandbox, so it does not depend on the current image

SHA-256 of `FlipperEmulator 5.3.bat`:

```
BEA373DB1B4AE2A8D24E8C1BEDE9399F8F99ABB4922BEADEEF1CA49ABF90F408
```

SHA-256 of `TestApps\native-hello-aarch64.fap.AppImage` (unchanged):

```
65AEDF3F93F67885B8C75ED4790D482ED391ADB8DC1378AA071F52047A36218F
```

The `Public Releases` folder contains:

- `FlipperEmulator 5.3.bat` - current public release
- `FlipperEmulator 4.1.bat` - previous public release
- `FlipperEmulator 3.0.bat` - public test build
- `FlipperEmulator 2.3.bat` - previous stable release
- `FlipperEmulator 1.0.bat` - legacy release

`FlipperEmulator 5.0.bat`, `FlipperEmulator 5.1.bat` and `FlipperEmulator 5.2.bat` are available only in `DevBuilds`. The 5.3 source is kept in both folders.

---

## Version 5.2 (previous development build)

Version **5.2** is a development build in `DevBuilds`; it is not part of `Public Releases`. It keeps the unofficial app shelf from 5.1 and makes the helper usable as one persistent console:

- **Persistent menu:** after every action except **8 Exit**, the menu returns. You can stop everything with **4** and then start another mode without running the `.bat` again. The console stays open until you choose **8**.
- **Option 3 is now "Flipper OS + File Manager":** it starts the Flipper OS if it is not running, starts the File Manager, and opens both in two browser tabs. If the OS is already running, it is reused and only the File Manager tab is added - QEMU is not restarted.
- **Option 2 reuses a running OS:** starting the real OS again while it is already running no longer restarts it.
- **No more "press S" prompt:** options 1, 2 and 3 start what is needed and return to the menu. Use **4 Stop everything** or the `stop` argument instead.
- **Native test app:** `TestApps\native-hello-aarch64.fap.AppImage` is a real standalone AppImage, not a browser page. It is an SDL2 Wayland program with a statically linked ARM64 CLI helper started from the same bundle. Installed through the shelf, it appears as **Native Hello** under **Apps** and draws its own screen on the emulated panel.
- **All 5.1 shelf features remain:** install, reinstall and remove from the File Manager, format checks, the Installed badge, PC backup and restore.

Verified before hand-off:

- Native Hello built, installed through the File Manager shelf, started from the App Manager, and rendered in the emulator: `HELLO WORLD`, `A REAL STANDALONE APPIMAGE`, `THIS IS NOT A BROWSER PAGE` and the CLI output `NATIVE AARCH64 PROCESS OK`
- option 4 stopped everything and the menu stayed usable; option 3 then started the OS and File Manager again
- option 3 with a running OS added only the File Manager tab and did not restart QEMU (same PID and start time)
- **8 Exit** closes the menu and leaves a running OS in the background
- clean boot with shelf version 5.2; `btrfs check --readonly` reports no errors

SHA-256 of `FlipperEmulator 5.2.bat`:

```
605A30AA344D7196AE909194C89896E80409B694F073F9AA55745707A3EB6D34
```

SHA-256 of `TestApps\native-hello-aarch64.fap.AppImage`:

```
65AEDF3F93F67885B8C75ED4790D482ED391ADB8DC1378AA071F52047A36218F
```

`FlipperEmulator 5.2.bat` remains available in `DevBuilds`; 5.3 is the current public release.

---

## Version 5.1 (previous development build)

Version **5.1** is a development build in `DevBuilds`; it is not part of `Public Releases`. It turns the File Manager into an unofficial app shelf, so your own Flipper app bundles can be installed and launched like the preinstalled apps:

- **Install from the File Manager**: upload a `.AppImage`, choose **Install**, and the bundle is copied to `/home/user/Apps`. It then appears in Flipper OS under **Apps**.
- **Installed badge and controls**: the File Manager marks installed bundles and offers **Reinstall** and **Remove**. The copy in `/home/user/Files` is kept as the store copy.
- **Format check before installing**: the shelf verifies the ELF header, type-2 AppImage magic and ARM64 machine type, then copies atomically and marks the bundle executable. Wrong-architecture, type-1 and non-AppImage files are rejected with a clear message.
- **Trust banner in the page**: the shelf explains that only trusted Flipper bundles work and that a stock AppImage without `app.toml` is ignored by Flipper OS.
- **App folder prepared in the image**: `/home/user/Apps` is created with mode `0775`, owned by the guest user, and the shelf service runs as `user`.
- **All 5.0 File Manager features remain**: upload, download, folders, rename, delete, Unicode names, drag-and-drop, PC backup and restore.
- **Updated in place**: starting 5.1 patches an existing image without losing installed apps or files. The one-time shelf update is skipped on later starts.

Verified before hand-off:

- install through the File Manager UI and through the local API, including the **Installed** badge and toast
- installed bundle is `0755`; `/home/user/Apps` is `0775`
- the new app appeared as a second **Browser** in the in-OS **Apps** list and started successfully
- **Reinstall** replaces the bundle; **Remove** deletes only the installed copy
- traversal, non-AppImage, type-1, wrong-architecture and non-ELF files are rejected
- existing Browser and Doom apps stayed untouched; the test app and its data were removed afterwards
- `btrfs check --readonly` reports no errors after the tests

SHA-256 of `FlipperEmulator 5.1.bat`:

```
B6A36B79B30B3F4BA993F82DA333A25269A67723108F78733EFFE74D7DE939B4
```

`FlipperEmulator 5.1.bat` remains available in `DevBuilds`; 5.3 is the current public release.

---

## Version 5.0 (development build)

Version **5.0** is a development build in `DevBuilds`; it was removed from `Public Releases`. It keeps both modes of 4.1 and adds a built-in File Manager, so your own files can be imported and tested without SSH, SCP or any manual Linux setup:

- **File Manager as menu option 3**, usable while the real Flipper OS from option 2 is running. No second virtual machine, no restart, same QEMU session.
- **Upload, download, folders, rename and delete** through a small local web page at `http://127.0.0.1:8898/`, with drag-and-drop, Unicode names, progress display and custom in-page dialogs.
- **Guest service** `flipper-files-shelf.service` runs as the unprivileged guest user `user` and writes to `/home/user/Files`. It starts automatically on every boot and needs only the Python standard library that is already in the image.
- **Automatic PC backup** in `%LOCALAPPDATA%\FlipperOneDemoFiles`, refreshed at every real-OS start and before an uninstall.
- **Automatic restore** after a reinstall or a fresh image, including subfolders, empty folders, Unicode names and regular file permissions.
- **Uninstall keeps your files**; the PC backup folder is not removed. Reinstall puts them back.
- **Direct App Manager link** from the File Manager page, so uploaded files can be tested immediately.
- **Updated menu and shortcuts**: File Manager, real OS, preview, PC backup and stop are all one click away.
- **Updated from 4.1 without losing apps or files**: the File Manager is added to the existing image on the next real-OS start. The older 4.1, 3.0, 2.3 and 1.0 releases remain unchanged.

Version 5.0 does not include the app shelf; use 5.3 for installing your own bundles.

SHA-256 of `FlipperEmulator 5.0.bat`:

```
61E2D4789C4006D33DD845A23B606C0BC510D0DFDDD4163221B446E5C377F45B
```

The `DevBuilds` folder keeps every build, including the 5.3, 5.2, 5.1 and 5.0 sources and the previous 4.1, 4.0 and 3.0 test builds. Older files are not modified by the helper.

---

## Version 4.1 (previous public release)

Version **4.1** was the previous public release. It kept both modes and all features of 4.0, with a safer and clearer one-time network setup:

- fully automatic internet access in the real Flipper OS through QEMU user-mode networking (NAT)
- the network profile is written atomically, so closing the window during the one-time setup cannot leave a half-written profile
- a clearer first-start message: the network step takes about 10 seconds and the console window must stay open until it finishes
- the installed copy now records the helper version in `installed.flag` while keeping the original installation date
- no changes to the preview, the app launcher or the QEMU/host networking setup

Version 4.1 remains available in `Public Releases` and `DevBuilds`.

SHA-256 of `FlipperEmulator 4.1.bat`:

```
E4588F88E8E04F65AC901D47E8903D87366EE358FB8E98F4DD7D8B1F8D89F0C1
```

---

## Version 4.0 (previous test build)

Version **4.0** was the test build that introduced fully automatic internet access to the real Flipper OS:

- QEMU user-mode networking (NAT) with a virtio adapter and a fixed MAC address
- automatic DHCP on every boot through a persistent `systemd-networkd` profile
- host reachable at `10.0.2.2`, DNS at `10.0.2.3`, internet through the Windows host
- the profile is written into the image once, idempotently, and matches only `virtio_net`, so real hardware is unaffected
- if the profile cannot be written, the image's built-in DHCP fallback keeps working

The network mechanism in 4.0 is unchanged in 4.1, 5.0, 5.1, 5.2 and 5.3. Version 4.0 remains available as a development test build:

- `DevBuilds\FlipperEmulator 4.0.bat`

---

## Version 3.0 (test build)

Version **3.0** is a public test build. It is based on 2.3 and makes installed apps work in the real Flipper OS mode. It includes:

- installed apps can be started from the Apps page or the in-OS App Manager
- Doom starts and renders on the emulated panel
- a software SDL renderer for hosted apps, because QEMU has no GPU
- a runtime-directory workaround for the missing logind seat in QEMU

The workaround sets `XDG_RUNTIME_DIR` and the SDL renderer through the kernel command line. It does not modify the Flipper OS image, so the image stays compatible with the normal installer and with 2.3.

Release files:

- `Public Releases\FlipperEmulator 3.0.bat`
- `DevBuilds\FlipperEmulator 3.0.bat`

---

## Version 2.3 (previous stable release)

Version **2.3** is an earlier stable release. It includes:

- the stable FlipCTL preview and the experimental real Flipper OS mode
- automatic WSL setup with one-time resume after a required restart
- automatic portable QEMU setup without administrator rights
- complete uninstall and fully automatic reinstall
- automatic restoration of the real-OS mode after a reinstall if it was used before
- refreshed installed copy and Start menu shortcuts when starting either mode

Version 2.3 also fixes the reinstall failure when the helper is started from its installed copy, and the menu no longer loops when console input is closed.

Release files:

- `Public Releases\FlipperEmulator 2.3.bat`
- `DevBuilds\FlipperEmulator 2.3.bat`

Version 1.0 remains available in `Public Releases` and `DevBuilds` as a legacy release.

---

## Contributing

Bug reports, ideas and pull requests are welcome. If you want to contribute:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a pull request

---

## License

Add your license here (for example MIT). This license covers **only the helper script in this repository**. All downloaded software remains under the licenses of their respective authors.

---

<sub>Flipper One and Flipper Devices are trademarks of their respective owners. This project is not affiliated with them.</sub>
