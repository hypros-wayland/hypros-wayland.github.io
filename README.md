# PlasmaTV Linux

[WARNING]
> This project has been discontinued.
> HyprOS will be soon released and the website will be overwritten.

An Arch Linux based distro that boots straight into a TV-first KDE Plasma
Bigscreen experience, with a classic Plasma Desktop available one click away.

## Highlights
- Custom **archiso** profile: Plymouth boot splash (stock `spinner` theme)
  on the live ISO, root auto-login on tty1 that drops straight into a
  `dialog`-based TUI installer.
- Installed system also boots with **Plymouth** (`spinner` theme), then
  **SDDM** with auto-login to `tv-user`.
- **Plasma Bigscreen** is the default session; a "Switch to Desktop" app
  flips SDDM to a normal Plasma Desktop session (and back, via "Switch to
  Bigscreen"), restarting the display manager to apply it.
- TV-style apps: 25 title-bar-less Electron streaming/music wrappers
  (Netflix, YouTube, YouTube Music, Disney+, Prime Video, Max, Hulu,
  Apple TV, Paramount+, Twitch, Spotify, Peacock, Crunchyroll, Plex,
  Tubi, Pluto TV, Discovery+, ESPN, Vimeo, Amazon Music, Deezer,
  SoundCloud, Sling TV, fuboTV, DAZN — each its own `.desktop` entry)
  and a first-boot **TV OOBE** wizard.
- Root password is `foobar` (change this before shipping to anyone but
  yourself — it's intentionally simple for a home-lab / hobby distro).

## Repo layout
```
archiso/                 -> custom archiso profile (based on releng)
  packages.x86_64        -> package list baked into the live ISO
  profiledef.sh           -> ISO metadata / build settings
  syslinux/, efiboot/, grub/ -> bootloader configs, taken as-is from the
                              official archiso releng profile (menu text
                              rebranded, BIOS menu reduced to a single
                              instant-boot "System0" entry) — these are
                              what makes the ISO actually bootable on
                              BIOS and UEFI
  airootfs/                -> files overlaid onto the live filesystem
    etc/mkinitcpio.conf.d/archiso.conf, etc/mkinitcpio.d/linux.preset
                              -> the archiso-aware initramfs config (also
                              taken from releng). Without these the live
                              ISO's initramfs can't find/mount the
                              squashfs and boot fails with
                              "Failed to switch root"
    root/install.sh        -> the dialog(1) installer, auto-run on tty1
    etc/systemd/system/getty@tty1.service.d/autologin.conf
                           -> agetty --login-program launches install.sh directly

skel/                     -> files copied onto the TARGET system by the
                              installer (via arch-chroot)
  etc/sddm.conf.d/autologin.conf
  usr/local/bin/switch-to-bigscreen
  usr/local/bin/switch-to-desktop
  usr/share/applications/*.desktop
  opt/plasmatv-apps/netflix-tv/     -> Electron kiosk wrapper
  opt/plasmatv-apps/tv-oobe/        -> first-boot TV-style OOBE
  etc/systemd/system/tv-oobe.service

installer/build.sh        -> convenience wrapper around `mkarchiso`
transform-existing-system.sh -> converts an already-installed Arch system
                              in place, no reinstall
optional/enable-selinux.sh -> opt-in, NOT run automatically — see warnings
                              inside. Unofficial/unsigned repo, replaces
                              core packages, real risk of breaking your
                              system. Installs in permissive mode only.
```

## Firmware / partition table / bootloader
`install.sh` detects the target's firmware and handles all three cases
differently, matching what each one actually needs:

| Firmware | Partition table | Bootloader |
|---|---|---|
| Legacy BIOS | GPT+`bios_grub` (default) or classic MBR — your choice | GRUB (`i386-pc`), single static `System0` entry, `timeout=0` |
| 32-bit (IA32) UEFI | GPT + ESP | GRUB (`i386-efi`, `--removable`), single static `System0` entry, `timeout=0` |
| 64-bit UEFI | GPT + ESP | **No bootloader at all** — a Unified Kernel Image is built and registered directly as an EFI boot entry named `System0` via `efibootmgr`. The firmware boots it with nothing in between. (Unsigned — disable Secure Boot or sign it yourself with `sbsigntools` if you need it on.) |

The BIOS/IA32 GRUB config is written directly (not via `grub-mkconfig`) so
it's exactly one entry, deterministically — `grub-mkconfig`'s
os-prober-driven template can't cleanly guarantee "only one entry named
System0" and would need to be re-forced after every kernel update anyway.

## Network setup during install
Before pacstrap, the installer actively sets up networking instead of
just failing with instructions:
- Checks `ip link` for a live ethernet carrier; if found, just waits
  briefly for DHCP via `nmcli`.
- Otherwise, if a Wi-Fi device exists, it scans and shows an interactive
  `dialog` menu of nearby networks (strongest signal per SSID, duplicates
  collapsed), prompts for a password (masked via `--insecure`), and
  connects with `nmcli`.
- Either way, a final `ping` (timeout-bounded) verifies real connectivity
  before continuing, with manual `nmcli` instructions if it still fails.

## Two real bugs that were fixed
If you built an earlier version of this repo, worth knowing what changed:
- **SDDM never autologged in**: the shipped `autologin.conf` had
  `DisplayServer=wayland` under `[General]`, which forces SDDM's *greeter*
  itself into its experimental Wayland mode (independent of which session
  the autologin'd user actually gets) — removed. Autologin no longer
  depends on that experimental code path.
- **Logging into tv-user immediately logged back out**: the "return to
  selector on logout" user unit was bound to `default.target`, which
  isn't reliably tied to the graphical session's actual lifecycle and
  could fire its `ExecStop` (which restarts SDDM) almost immediately
  after login. Rebound to `graphical-session.target`, which Plasma itself
  starts once the session is genuinely up and stops on logout.

## Locked down by default
- Root gets a password set only so a hash exists, then immediately
  `passwd -l root` — no interactive root login anywhere, console or
  otherwise. `tv-user` has full `sudo` via `wheel` for anything that needs it.
- `getty@tty2` through `tty6`, `autovt@`, and `serial-getty@` are masked —
  there's no login prompt reachable except through SDDM's autologin flow.

## Converting an existing Arch install (no reinstall)
Already running Arch (or an Arch-based distro) and don't want to
reinstall? Run:
```bash
cd PlasmaTV-Linux
sudo ./transform-existing-system.sh
```
It installs the PlasmaTV package set, copies `skel/` onto your real root,
creates `tv-user`/`selector-user`, wires up the Plymouth splash, points
SDDM's autologin at the user selector, enables the PlasmaTV services,
detects VMware and installs `open-vm-tools` if relevant, optionally
removes any other display manager (gdm/lightdm/lxdm) that would fight
SDDM's autologin, and cleans up orphaned dependencies afterward
(`pacman -Qtdq` → `pacman -Rns`). It does **not** touch your disk
partitioning, hostname, locale, or existing (non-PlasmaTV) user accounts.
Safe to re-run.

## Building the ISO
```bash
sudo pacman -S --needed archiso
git clone <this repo> PlasmaTV-Linux && cd PlasmaTV-Linux
sudo ./installer/build.sh
# -> out/plasmatv-linux-YYYY.MM.DD-x86_64.iso
```

## Boot the ISO
Root auto-logs in on tty1 and immediately launches the dialog installer
(`archiso/airootfs/root/install.sh`, copied to `/root/install.sh` on the live
system). Follow the prompts: pick a disk, confirm the wipe, and it partitions
(UEFI: ESP + ext4 root), pacstraps the base + Plasma Bigscreen + SDDM +
Plymouth, chroots in to configure the bootloader/locale/hostname, creates
`tv-user`, sets `root`'s password to `foobar`, drops in the `skel/` files,
and enables the right services.

## Notes / things to double check on real hardware
- Plymouth now shows on the live ISO boot too (spinner theme, `quiet
  splash` on the kernel cmdline), not just the installed system.
- The BIOS (syslinux) boot menu is a single "System0" entry with a
  0.1s timeout — as close to GRUB's `TIMEOUT=0` semantics as syslinux
  gets (syslinux's own `TIMEOUT 0` means "wait forever", the opposite).
  The UEFI (systemd-boot) menu is untouched and still shows the normal
  multi-entry menu with a 15s timeout.
- No `pulseaudio` package — audio uses `pipewire` + `pipewire-pulse` +
  `wireplumber`, the modern PulseAudio-compatible stack that ships on
  fresh Arch/Plasma installs today.
- On VMware, both `install.sh` (fresh installs) and
  `transform-existing-system.sh` (in-place conversions) auto-detect the
  hypervisor via `systemd-detect-virt` and install/enable `open-vm-tools`.
- `plasma-bigscreen` ships a Wayland session file — confirm its exact name
  with `ls /usr/share/wayland-sessions/` after a first install and adjust
  `skel/etc/sddm.conf.d/autologin.conf` + the switch scripts if it differs
  from `plasma-bigscreen.desktop`.
- Electron isn't in the official Arch repos in all cases; the netflix-tv app
  assumes an AUR helper (`yay`) is available, or you vendor a prebuilt
  Electron binary. `install.sh` has a clearly marked TODO for this.
- The TV OOBE is a working scaffold (language + Wi-Fi via `nmcli` + finish)
  meant to be restyled/expanded — it's plain HTML/CSS/JS running in Electron
  kiosk mode, not a finished product.
