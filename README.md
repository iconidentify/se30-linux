# se30-linux

Debian GNU/Linux (sid, m68k) with Linux 7.2.8, set up for the Macintosh SE/30. It runs from one SCSI disk, such as a SCSI2SD card, that holds a small System 7.1 volume to boot from and a Linux root partition.

- **Status.** It boots and runs X on a real SE/30 (68 MB, a 32-bit-clean ROM, a SCSI2SD), and is tested in MAME and QEMU.
- **Booting.** It boots from [se30boot](https://github.com/iconidentify/se30boot), a boot menu that doesn't need Mac OS, or from Penguin.
- **Companion project.** [se30os](https://github.com/iconidentify/se30os) is an operating system written from scratch for the same machine.

## What you get

- **Kernel.** Linux 7.2.8 in a lean 68030-only configuration (`src/build/kernel-lean2.config`).
  - It adds a fast path for glibc's `get_thread_area` calls, cutting syscall cost by 15%.
  - The kernel embeds a small BusyBox initramfs, which mounts the root partition.
- **System.**
  - Debian sid m68k, with BusyBox as init.
  - A root shell on the screen and a login on the modem port at 9600 baud. Root has no password.
  - A static network setup in `/etc/network.conf`; `MODE=dhcp` switches to DHCP. Telnet is open on the LAN.
- **X.** `startx` runs TinyX (`Xfbdev`), patched for the Mac's 1-bit screen, with twm and rxvt.
  - The pointer is drawn onto the framebuffer from the input signal handler, so it keeps up while X is busy.
  - Option-click is button 2 and Control-click is button 3.
  - `startx-xvfb` is the older fallback: Xvfb plus `se30fb`, a bridge that dithers to 1 bpp.
- **Benchmarks.** `se30bench [-t|-x]` times everything, and `benchmarks/` holds the results. In MAME:
  - TinyX is ready in 124 s, against 411 s for the first Xvfb setup.
  - A terminal starts in 4.9 s, against 47 s for xterm.
  - A bash login takes 1.0 s, and the mouse pointer's p90 latency under load is 24 ms.

## The disk

| Partition | Contents |
|---|---|
| 1 | Apple partition map |
| 2 | Apple SCSI driver |
| 3 | Mac volume, 256 MB HFS: System 7.1 with 32-bit addressing on. Its `Linux` folder holds `vmlinux.gz` (Penguin), `vmlinux` (se30boot), Penguin 17 and 19, and se30boot's files. |
| 4 | Linux root, 1.6 GB ext4, label `se30root`, `/dev/sda4` |

**Booting it:**
- **With se30boot.** Pick Linux in the menu at startup. se30boot loads the unpacked `vmlinux` in seconds.
- **With Penguin 19.** Boot Now (⌘B) with the kernel and command line saved in its settings: `console=ttyS0,9600 console=tty0`.
- **If Penguin 19 can't read the MMU tables.** Use Penguin 17 with "Use old RAM detection".

## Building

`src/build/` holds the scripts as they were used, rather than a single one-command build. They run in the `se30-build` container (`src/build/Dockerfile.se30-build`, plus `Dockerfile.se30-xbuild` for TinyX), with `/build` as the work directory.

1. **Root filesystem.**
   - `mkdebroot.sh` bootstraps Debian sid m68k from debian-ports with mmdebstrap.
   - `debian-overlay/` is laid over it: init scripts, network, profile, X startup, `se30bench`.
2. **Kernel.**
   - Start from Linux 7.2.8 with `kernel-lean2.config` (or `lean.sh` on `kernel-base.config`) and `src/patches/linux-m68k-get_thread_area-fastpath.patch`.
   - `kbuild.sh` builds it, embedding the initramfs that `mkramroot.sh` stages from `initramfs/`.
3. **X.**
   - `xbuild-tinyx.sh` cross-compiles libXfont 1.5.4 and TinyX (from tinycorelinux/tinyx) with `src/patches/tinyx-se30.patch` and `tinyx-se30-hwcursor.patch`.
   - rxvt 2.6.4 is configured as in `src/patches/rxvt-2.6.4-config.txt`.
   - Both builds go into `debian-overlay/usr/local/bin/` as `Xfbdev` and `rxvt`. They are not in the repository.
   - `se30fb.c` is the Xvfb bridge.
4. **The disk image.**
   - Start from an image of your own SCSI disk with System 7.1 on it. Apple's system software is not distributed here.
   - `relayout.py` shrinks the HFS volume in place and adds the Linux partition.
   - `mkcard.sh`, `mkfinal.sh`, `mkext4.sh`, `mkimage.sh` and `mkcard-v3.sh` assemble the card.
   - `mkvariant.sh` with the `hook-*.sh` scripts makes test variants.

## Testing

`src/test-harness/` drives the emulators.

- **MAME.** `mame/` holds the `macse30` remote control (Lua), mouse homing and a serial bridge.
  - `bench.sh` and `runbench.sh` time a disk image, and `compare.py` compares runs.
  - `cursorlat.c` measures pointer latency.
- **QEMU.** `qemu/qtool.py` drives QEMU's `q800`. The lean kernel is 68030-only, so QEMU needs a 68040 build.

## Known issues

- **Asante Ethernet transmit.** The MacCon 30si is found by `mac8390` and receives packets, but nothing it transmits reaches the wire. se30os's driver sends and receives on the same card, so the fix is to be found by comparing the two.
- **SCSI pseudo-DMA.** MAME's pseudo-DMA crashes Linux, so the test setups add `mac_scsi.setup_use_pdma=0`. On real hardware the disk is several times faster without it.
- **The ADB keyboard in MAME.** It doesn't reach Linux there, an emulation gap; the serial login works.

## Releases

Releases carry the kernel the card uses, `vmlinux.gz`. Its source is Linux 7.2.8 from kernel.org with `src/build/kernel-lean2.config` and `src/patches/linux-m68k-get_thread_area-fastpath.patch`. The disk images themselves are not published, because they contain Apple's System 7.1.

## Licence

- **Our files** (scripts, configuration, overlays, `se30fb.c`, test harness, documentation) are MIT, see `LICENSE`.
- **Patches** keep their upstream licences: the Linux patch is GPL-2.0, and the TinyX patches are under TinyX's MIT/X11 licence.
- **The distributed kernel** is GPL-2.0.
