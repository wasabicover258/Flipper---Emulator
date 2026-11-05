# Flipper One Demo for Windows

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D6)
![Requires](https://img.shields.io/badge/requires-WSL%202-blue)
![Status](https://img.shields.io/badge/status-unofficial-orange)
![Version](https://img.shields.io/badge/version-4.1_stable-brightgreen)

Try the **Flipper One** user interface on any Windows PC - no device, no extra hardware, no manual setup.

A single double-click on `FlipperEmulator 4.1.bat` downloads everything it needs, sets up an isolated Linux environment, and lets you choose between two modes:

- **FlipCTL preview** - the fast, stable test UI from the Flipper One image. Hardware features are simulated.
- **Real Flipper OS** - the actual Flipper OS kernel and initramfs, booted in QEMU (aarch64) on your PC. Experimental.

> **Stable helper, experimental emulation:** 4.1 is the stable release of this Windows helper. The real-OS mode itself remains experimental because QEMU emulates hardware the image was not built for.

> **Disclaimer:** This is an unofficial community project. It is **not** affiliated with or endorsed by Flipper Devices. This repository contains no Flipper software - the helper only downloads publicly available components from their official sources.

---

## Table of Contents

- [What is this?](#what-is-this)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Real Flipper OS Mode](#real-flipper-os-mode)
- [Internet Access (NAT)](#internet-access-nat)
- [How It Works](#how-it-works)
- [What Gets Installed](#what-gets-installed)
- [Uninstalling](#uninstalling)
- [Reinstalling](#reinstalling)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Security Note](#security-note)
- [Version 4.1 (stable release)](#version-41-stable-release)
- [Version 4.0 (previous test build)](#version-40-previous-test-build)
- [Version 3.0 (test build)](#version-30-test-build)
- [Version 2.3 (previous stable release)](#version-23-previous-stable-release)
- [Contributing](#contributing)
- [License](#license)

---

## What is this?

The Flipper One software is under active development and is, by design, meant to run on the actual device. This project makes it possible to get a first impression of the interface - and to test it - directly on a Windows PC.

The helper provides two ways to use it:

### FlipCTL preview

The preview runs the **FlipCTL test version** of the Flipper One UI. It is rendered in your browser and talks to a local test server, so everything works without real hardware. Features that depend on physical components (Wi-Fi, modem, battery, GPIO, etc.) are **dummies**.

### Real Flipper OS

The real-OS mode boots the actual Flipper OS kernel and initramfs from the public Flipper One image inside QEMU. The image targets a Rockchip RK3576 (ARM) board, so the hardware is fully emulated on your PC. This is useful for testing the real system, but it is slower than real hardware and cannot use your PC's Wi-Fi, modem, battery or GPIO.

---

## Requirements

| Requirement | Details |
|---|---|
| **OS** | 64-bit Windows 10 or Windows 11 |
| **WSL 2** | Windows Subsystem for Linux 2. The helper installs it if it is missing. |
| **Virtualization** | Must be enabled in the BIOS/UEFI for WSL 2. |
| **Browser** | Microsoft Edge or Google Chrome recommended. Both modes open in your default browser; one of Edge/Chrome is additionally used as a hidden device renderer for the preview. |
| **Disk space** | Plan for about 12 GB free during setup. The finished installation uses about 8-9 GB. |
| **Internet** | Required for setup and reinstall. Normal use works offline. |
| **RAM** | 8 GB recommended for the real OS. The preview runs on less. |
| **Administrator rights** | The app and QEMU do not need administrator rights. Windows may ask once for permission to enable WSL. |

---

## Quick Start

1. **Download** `FlipperEmulator 4.1.bat` from the `Public Releases` folder. This is the stable release. Older versions remain available in `Public Releases` and `DevBuilds`.
2. **Double-click** the file. You can keep it anywhere; the helper installs its own copy.
3. **Wait** while the first-time setup runs. It downloads several GB and may take a while.
4. When the menu appears, choose **1** for the FlipCTL preview or **2** for the real Flipper OS. Pressing **Enter** starts the preview.
5. Your browser opens automatically. Done.

> **First time using WSL?** If WSL is not set up yet, the helper starts its installation (you will be asked to confirm one administrator prompt). Windows may require a restart. The helper registers a one-time auto-resume, so setup continues after you sign in again. If it does not continue automatically, simply double-click the file again.

After the first successful setup, the helper stores a copy at `%LOCALAPPDATA%\FlipperOneDemo\Flipper-One-Demo.bat` and creates Start menu shortcuts.

---

## Usage

After setup, running the file shows a simple menu:

```
[1] FlipCTL preview  (fast, stable)
[2] Real Flipper OS  (experimental, QEMU emulation)
[3] Stop everything
[4] Uninstall everything
[5] Reinstall
[6] Show server log
[7] Exit
  Status: stopped
```

| Option | What it does |
|---|---|
| **1** | Starts the FlipCTL preview server and opens the UI in your browser. |
| **2** | Boots the real Flipper OS in QEMU and opens it in your browser. |
| **3** | Stops the preview server, the hidden device browser and QEMU. |
| **4** | Removes the private Linux environment, all downloaded files, portable QEMU, settings and shortcuts. |
| **5** | Performs a full uninstall and a fresh automatic reinstall. It restores the real Flipper OS if you used it before; otherwise the FlipCTL preview. |
| **6** | Shows the last lines of the preview server log. |
| **7** | Closes the menu. A running preview or real OS keeps running in the background. |

Press **Enter** to accept the default (**1**, FlipCTL preview), or type a number and confirm.

### Start menu shortcuts

On the first successful setup, three shortcuts are created under **Flipper One Demo** in the Start menu:

- **Flipper One Demo** - opens the menu.
- **Start FlipCTL Preview** - starts option 1 directly.
- **Stop Flipper One** - stops everything.

### Command-line arguments

The helper also accepts these command-line arguments:

| Argument | Action |
|---|---|
| `start` | Start the FlipCTL preview and open the browser. |
| `stop` | Stop the preview, the hidden browser and QEMU. |
| `real` or `realos` | Start the real Flipper OS. |
| `log` | Show the last lines of the preview server log. |
| `uninstall` | Remove everything without asking for confirmation. |
| `qemu` | Download and prepare the portable QEMU emulator. |
| `install` | Set up or repair the installation without starting the app. |
| `reinstall` | Full uninstall and fresh setup, then restore the real Flipper OS if it was used before; otherwise the FlipCTL preview. |
| `resume` | Internal one-time resume after a required Windows restart. |

`start` and `real` still show the final "press S or Enter" prompt; use **[3] Stop everything** or the `stop` argument to stop the app. `stop`, `log`, `uninstall`, `qemu` and `install` run without prompts; `reinstall` still asks for the YES confirmation.

Example:

```bat
FlipperEmulator 4.1.bat start
FlipperEmulator 4.1.bat real
FlipperEmulator 4.1.bat stop
```

### Stopping the app

The preview and the real OS keep running in the background, even if you close the console window. To stop them:

- Start menu -> **Flipper One Demo** -> **Stop Flipper One**
- Run the file again and choose **[3] Stop everything**
- Type **S** in the console window right after starting

Closing the console window or choosing **[7] Exit** does not stop a running instance.

---

## Real Flipper OS Mode

The real-OS mode is experimental. It boots the actual Flipper OS kernel and initramfs from the public image, with the image's root filesystem mounted read-write.

- **Emulation:** QEMU `virt` machine with a Cortex-A72 CPU and TCG software emulation. No ARM hardware is required.
- **Internet:** automatic. The guest uses QEMU user-mode networking (NAT), receives `10.0.2.15` by DHCP and can reach the host at `10.0.2.2`, DNS at `10.0.2.3` and the internet. Nothing has to be configured, inside or outside the guest.
- **Memory/CPU:** The helper sizes QEMU to your PC (2-4 GB RAM, up to 4 vCPUs).
- **First start:** Usually 1-3 minutes. Slower PCs may take longer. The helper waits up to 7 minutes before showing a warning.
- **One-time network setup:** On the first real-OS start, the helper adds the DHCP profile to the image. This takes about 10 seconds; keep the console window open until that step has finished. If it is interrupted, the next start safely retries.
- **URL:** `http://127.0.0.1:8899/` by default. If port 8899 is busy, the helper picks the next free local port and opens it automatically.
- **Persistence:** The raw image is writable, so changes made inside the emulated OS persist until you reinstall.
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

- **Outbound only.** The guest can reach the internet and the Windows host. Incoming connections are not forwarded, except the UI port that the helper publishes on `127.0.0.1`.
- `10.0.2.2` is the **Windows host**, not the WSL distribution. WSL has its own virtual network behind Windows.
- Wi-Fi, modem and Bluetooth errors in the guest log are expected: that hardware does not exist in QEMU. They do not block the boot and do not affect internet access.
- The `stun.services.mozilla.com` messages in the flipctl log are harmless: that hostname no longer exists.

---

## How It Works

1. **WSL check** - verifies that WSL 2 is available and installs it if necessary. This is the only step that may ask for administrator permission and may require a restart.
2. **Private Linux environment** - imports an Ubuntu 24.04 base system as a dedicated WSL distribution named `FlipperOne`. Your existing WSL distributions are not touched.
3. **Image download and decompression** - downloads the public Flipper One image (about 2 GB compressed) and decompresses it to a raw image of about 6 GB with portable zstd. The compressed download is deleted afterwards; the raw image is kept because the real-OS mode needs it.
4. **Extraction** - mounts the image read-only inside the private WSL distribution and extracts the FlipCTL preview UI, the kernel and the initramfs.
5. **Preview setup** - installs Node.js inside the private environment, runs the FlipCTL test server on port 8899 and starts a hidden Edge/Chrome instance that identifies itself like the device browser.
6. **Network profile** - on the first real-OS start, mounts the image read-write once and adds a matching `systemd-networkd` DHCP profile for the QEMU network adapter. The file is replaced atomically, the write is idempotent and only the `@Minimal` subvolume is touched.
7. **Real-OS setup** - uses an existing system QEMU or prepares the portable QEMU. It then boots the extracted kernel and initramfs with the raw image, forwards a localhost port to the guest and waits for the web UI.
8. **Browser** - opens the preview or the real OS in your normal browser. Everything runs locally; no cloud service is involved.

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
| WSL itself (only if it was missing) | Windows component | Microsoft |

Everything the helper manages is stored in:

- `%LOCALAPPDATA%\FlipperOneDemo` - app files, image, logs, tools and optionally QEMU
- a private WSL distribution named `FlipperOne`
- Start menu shortcuts under **Flipper One Demo**

If QEMU is already installed system-wide, it is reused but not modified. Nothing else is installed outside these locations, apart from WSL itself if it was missing.

### Disk space

- Finished installation: about **8-9 GB** (about 6 GB image + about 2 GB WSL distribution, plus tools and optional portable QEMU).
- During setup: plan for about **12 GB free** because the compressed download, the raw image and the Linux environment exist at the same time.

---

## Uninstalling

Run the file and choose **[4] Uninstall everything**. Type **YES** to confirm.

This removes:

- the private WSL distribution `FlipperOne`
- the complete `%LOCALAPPDATA%\FlipperOneDemo` folder
- the downloaded Flipper One image, logs and browser profile
- portable QEMU and the helper tools
- the Start menu shortcuts
- the one-time auto-resume entry

It does **not** remove:

- other WSL distributions
- WSL itself
- a system-wide QEMU installation
- the downloaded `.bat` file you saved outside the app folder

If you run uninstall from the installed copy, the last file is deleted a few seconds after the window closes. Wait a moment before checking the folder. If files remain, close all browser windows and try again; if the WSL distribution is busy, restart Windows and repeat the uninstall.

---

## Reinstalling

Run the file and choose **[5] Reinstall**. Type **YES** to confirm.

A reinstall performs a complete uninstall followed by a fresh automatic setup. It needs an internet connection and the same free disk space as the first installation.

The helper remembers whether you actually used the real Flipper OS. After a reinstall it restores that mode automatically:

- real Flipper OS if you used it before
- FlipCTL preview otherwise

You can switch modes at any time with **[1]** and **[2]**.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| **"WSL could not be installed"** | Allow the administrator prompt. If it still fails, open an administrator PowerShell and run `wsl --install --no-distribution`, then restart your PC. |
| **Setup stops after a restart** | Double-click the file again. The one-time auto-resume normally continues automatically, but a manual restart works too. |
| **"Import failed"** | Make sure virtualization is enabled in your BIOS/UEFI and that WSL 2 is available. |
| **"Loop devices are not available"** | Run `wsl --update` in PowerShell and try again. |
| **Download fails** | Check your internet connection and run the file again. Incomplete downloads are restarted automatically. |
| **Blank preview page or server not responding** | Choose **[6] Show server log**, or try **[5] Reinstall**. |
| **Port 8899 is busy** | Close the program using port 8899. The preview needs this port. The real-OS mode chooses the next free port automatically. |
| **Real Flipper OS does not boot** | Wait up to 7 minutes. Check `%LOCALAPPDATA%\FlipperOneDemo\realos\serial.log` and `qemu.err.log`. The image is built for RK3576 hardware; emulation may not work on every PC. Try **[5] Reinstall**. |
| **An app does not appear in the real OS** | Wait a few minutes: software emulation is slow, and Doom in particular takes time to mount and start. Then try the app again from the Apps page or the in-OS App Manager. Apps that need a real GPU may not work. |
| **No internet in the real OS** | Close and start the real OS again. On the first start, wait for the one-time network profile to finish (about 10 seconds) and keep the console window open. Inside the guest, `10.0.2.2` is the Windows host and `10.0.2.3` is DNS. If a reinstall also fails, include the last lines of `qemu.err.log` in an issue. |
| **Ping fails but websites load** | Windows may block QEMU's ICMP forwarding on some systems. TCP and DNS still work, so the guest has internet. Test with a browser or a normal download. |
| **QEMU download fails** | If a system QEMU is installed, it is used automatically. Otherwise check your connection and run `FlipperEmulator 4.1.bat qemu` to retry the portable download. |
| **No browser found** | Install Microsoft Edge or Google Chrome. The preview needs one of them for the hidden device renderer. |
| **Uninstall leaves files behind** | Close all browser windows and retry. If the private WSL distribution is busy, restart Windows and run uninstall again. |
| **Antivirus blocks a download** | The helper downloads large tools from official sources. Allow the files after checking them, then retry. |

If the problem persists, open an issue and include the output of **[6] Show server log**. For real-OS problems, also include the last lines of `serial.log` and `qemu.err.log`.

---

## Limitations

- The **FlipCTL preview** is a test/demo UI. There is no real hardware behind it; Wi-Fi, modem, battery and other hardware features are dummies.
- The **real Flipper OS** mode is experimental. It runs under QEMU software emulation, is slower than real hardware and cannot access your PC's hardware.
- The real OS is built for a Rockchip RK3576 board. Some image versions may change the internal structure and require an update of this helper.
- The helper requires WSL 2 and virtualization. It is not available on systems where virtualization is disabled or unsupported.
- The real-OS image is writable. Changes persist locally until you reinstall.
- Internet access in the real OS is **outbound only** (QEMU user-mode NAT). The guest is not reachable from your local network.

---

## Security Note

The `.bat` file is plain text. It launches an embedded PowerShell script with `-ExecutionPolicy Bypass` for that one process only and downloads several large files.

- Downloads come from official sources: `dl-linux-images.flipp.dev`, `cloud-images.ubuntu.com`, `nodejs.org`, GitHub (`meta/zstd`), `7-zip.org` and `qemu.weilnetz.de`.
- The 7-Zip MSI is verified with SHA-256. QEMU checksums are verified when the mirror provides them.
- The preview server and the real-OS port forwarding listen on **localhost only**.
- The helper does not collect telemetry or send data to a cloud service.

As with any script from the internet, **please read it before you run it**.

---

## Version 4.1 (stable release)

Version **4.1** is the stable release. It keeps both modes and all features of 4.0, with a safer and clearer one-time network setup:

- fully automatic internet access in the real Flipper OS through QEMU user-mode networking (NAT)
- the network profile is written atomically, so closing the window during the one-time setup cannot leave a half-written profile
- a clearer first-start message: the network step takes about 10 seconds and the console window must stay open until it finishes
- the installed copy now records the helper version in `installed.flag` while keeping the original installation date
- no changes to the preview, the app launcher or the QEMU/host networking setup

Verified before release:

- complete fresh installation from an empty state, including WSL import, image download, decompression and first boot
- complete reinstall through option 5, including a fresh image download and automatic re-application of the network profile
- option 4 (uninstall) removes the private environment, files and Start menu shortcuts again
- real boot: `eth0` uses `10-qemu-nat.network`, receives `10.0.2.15/24`, gateway `10.0.2.2` and DNS `10.0.2.3`; ICMP, DNS resolution and HTTP all work
- Doom starts from the App Manager, renders on the emulated panel and runs under software emulation
- the FlipCTL preview still starts, responds and stops cleanly
- upgrading an existing 4.0 image keeps the installed apps and does not rewrite the network profile
- `btrfs check --readonly` reports no errors after the tests

The `Public Releases` folder contains:

- `FlipperEmulator 4.1.bat` - stable release
- `FlipperEmulator 3.0.bat` - public test build
- `FlipperEmulator 2.3.bat` - previous stable release
- `FlipperEmulator 1.0.bat` - legacy release

The `DevBuilds` folder keeps every build, including the 4.1 source and the previous 4.0 test build. Older files are not modified by the helper.

---

## Version 4.0 (previous test build)

Version **4.0** was the test build that introduced fully automatic internet access to the real Flipper OS:

- QEMU user-mode networking (NAT) with a virtio adapter and a fixed MAC address
- automatic DHCP on every boot through a persistent `systemd-networkd` profile
- host reachable at `10.0.2.2`, DNS at `10.0.2.3`, internet through the Windows host
- the profile is written into the image once, idempotently, and matches only `virtio_net`, so real hardware is unaffected
- if the profile cannot be written, the image's built-in DHCP fallback keeps working

The network mechanism in 4.0 is unchanged in 4.1. Version 4.0 remains available as a development test build:

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

Version **2.3** is the previous stable release. It includes:

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

Add your license here (for example MIT). This license covers **only the helper script in this repository**. All downloaded software remains under the licenses of its respective authors.

---

<sub>Flipper One and Flipper Devices are trademarks of their respective owners. This project is not affiliated with them.</sub>
