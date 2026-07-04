#!/usr/bin/env bash
# transform-existing-system.sh
#
# Converts an ALREADY INSTALLED Arch (or Arch-based) system into PlasmaTV
# Linux in place — no reinstall, no wiped disk. Run this from a normal
# terminal as root on the machine you want converted.
#
# What it does:
#   1. Installs the PlasmaTV package set (skips anything already present)
#   2. Copies the PlasmaTV skel/ tree onto your real root filesystem
#   3. Creates tv-user and selector-user if they don't already exist
#   4. Sets up the PlasmaTV config store, sudoers scoping, and services
#   5. Adds the plymouth hook + stock spinner theme, best-effort bootloader
#      config (GRUB only — see warnings for systemd-boot/other)
#   6. Detects VMware and installs/enables open-vm-tools
#   7. Offers to disable/remove other display managers that would fight
#      SDDM's autologin (gdm/lightdm/lxdm), and cleans up orphaned
#      dependencies left behind by anything it removes
#
# What it deliberately does NOT touch: your hostname, locale, timezone,
# existing user accounts (other than tv-user/selector-user), disk
# partitioning, or your existing kernel.
#
# Safe to re-run — most steps check for existing state first.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run this as root (sudo $0)." >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKEL="$REPO_DIR/skel"
LOG=/tmp/plasmatv-transform.log
: > "$LOG"

log()  { echo "$*" | tee -a "$LOG"; }
run()  { echo "+ $*" >> "$LOG"; "$@" >> "$LOG" 2>&1; }
warn() { echo "WARNING: $*" | tee -a "$LOG" >&2; }

[ -d "$SKEL" ] || { echo "Can't find skel/ next to this script — run it from inside the PlasmaTV-Linux repo." >&2; exit 1; }
command -v pacman >/dev/null || { echo "This isn't an Arch-based system (no pacman found)." >&2; exit 1; }

echo "=================================================================="
echo " PlasmaTV Linux — in-place transform"
echo "=================================================================="
echo "This will install packages, create tv-user/selector-user, change"
echo "SDDM's autologin target, and (optionally) remove other display"
echo "managers. It will NOT touch your disk layout or existing users."
echo
read -rp "Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# 1. Virtualization detection
# ---------------------------------------------------------------------------
VIRT=$(systemd-detect-virt 2>/dev/null || echo none)
EXTRA_PKGS=()
if [ "$VIRT" = "vmware" ]; then
    log "==> VMware detected — will install open-vm-tools"
    EXTRA_PKGS+=(open-vm-tools)
fi

# ---------------------------------------------------------------------------
# 2. Install the PlasmaTV package set
# ---------------------------------------------------------------------------
log "==> Installing packages (this can take a while)..."
mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$REPO_DIR/archiso/packages.x86_64" | grep -vE '^(mkinitcpio-archiso|syslinux|dialog|arch-install-scripts|linux|linux-firmware|memtest86\+|memtest86\+-efi|edk2-shell)$')
if ! run pacman -Sy --needed --noconfirm "${PKGS[@]}" "${EXTRA_PKGS[@]}"; then
    echo "Package install failed — see $LOG" >&2
    exit 1
fi

if [ "$VIRT" = "vmware" ]; then
    systemctl enable --now vmtoolsd.service 2>/dev/null || true
    systemctl enable --now vmware-vmblock-fuse.service 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 3. Copy the skel/ tree onto the real filesystem
# ---------------------------------------------------------------------------
log "==> Copying PlasmaTV files onto the system..."
run cp -a "$SKEL/." /

# ---------------------------------------------------------------------------
# 4. Users
# ---------------------------------------------------------------------------
log "==> Setting up tv-user / selector-user..."
if ! id tv-user &>/dev/null; then
    useradd -m -G wheel,video,audio,input -s /bin/bash tv-user
    read -rsp "Set a password for tv-user: " TVPASS; echo
    echo "tv-user:${TVPASS:-foobar}" | chpasswd
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
else
    log "    tv-user already exists — leaving it alone"
fi

if ! id selector-user &>/dev/null; then
    useradd -m -s /usr/sbin/nologin selector-user
    passwd -l selector-user >/dev/null
else
    log "    selector-user already exists — leaving it alone"
fi

install -d -m755 "/home/tv-user/.config/systemd/user/graphical-session.target.wants"
ln -sf /etc/plasmatv/skel-user-units/plasmatv-return-to-selector.service \
  "/home/tv-user/.config/systemd/user/graphical-session.target.wants/plasmatv-return-to-selector.service"
chown -R tv-user:tv-user "/home/tv-user/.config" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. PlasmaTV config store
# ---------------------------------------------------------------------------
mkdir -p /etc/plasmatv /var/lib/plasmatv/screentime
[ -f /etc/plasmatv/users-secrets.json ] || echo '{}' > /etc/plasmatv/users-secrets.json
chmod 600 /etc/plasmatv/users-secrets.json
chmod 644 /etc/plasmatv/users-public.json

mkdir -p /usr/local/lib/plasmatv-child-bin
rm -f /usr/local/lib/plasmatv-child-bin/.gitkeep
ln -sf "$(command -v electron || echo /usr/bin/electron)" /usr/local/lib/plasmatv-child-bin/electron

# ---------------------------------------------------------------------------
# 6. Plymouth splash
# ---------------------------------------------------------------------------
log "==> Enabling Plymouth boot splash..."
if grep -q '^HOOKS=(base udev autodetect' /etc/mkinitcpio.conf 2>/dev/null; then
    sed -i 's/^HOOKS=(base udev autodetect/HOOKS=(base udev plymouth autodetect/' /etc/mkinitcpio.conf
    run mkinitcpio -P
else
    warn "Couldn't find the expected HOOKS= line in /etc/mkinitcpio.conf — add 'plymouth' to your HOOKS manually, then run 'mkinitcpio -P'."
fi
plymouth-set-default-theme -R spinner 2>/dev/null || warn "plymouth-set-default-theme failed — check that plymouth installed correctly."

if [ -f /boot/grub/grub.cfg ] && command -v grub-mkconfig >/dev/null; then
    # Deliberately NOT forcing the fresh-install's single "System0" entry
    # here — this is converting an arbitrary existing system that may
    # dual-boot or have other kernels/OSes GRUB already knows about, and
    # collapsing that down unasked would be destructive. Just adds the
    # Plymouth splash to whatever menu you already have.
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    run grub-mkconfig -o /boot/grub/grub.cfg
elif command -v bootctl >/dev/null && bootctl is-installed &>/dev/null; then
    warn "Detected systemd-boot — add 'quiet splash' to your kernel command line in /boot/loader/entries/*.conf manually."
else
    warn "Couldn't identify your bootloader — add 'quiet splash' to your kernel cmdline manually to see the Plymouth splash."
fi

# ---------------------------------------------------------------------------
# 7. SDDM autologin -> selector
# ---------------------------------------------------------------------------
log "==> Pointing SDDM's autologin at the PlasmaTV user selector..."
[ -f /etc/sddm.conf.d/autologin.conf ] || mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << 'EOF'
[Autologin]
User=selector-user
Session=plasmatv-selector.desktop
Relogin=true

[General]
DisplayServer=wayland
EOF

# ---------------------------------------------------------------------------
# 8. Services
# ---------------------------------------------------------------------------
log "==> Enabling services..."
systemctl enable NetworkManager 2>/dev/null || warn "Couldn't enable NetworkManager — if you're using systemd-networkd/iwd instead, that's fine, just leave it."
systemctl enable sddm
systemctl enable bluetooth 2>/dev/null || true
systemctl enable tv-oobe.service 2>/dev/null || true
systemctl enable plasmatv-dns-rules.service
systemctl enable plasmatv-timelimit-daemon.service
touch /etc/plasmatv-first-boot

# ---------------------------------------------------------------------------
# 8b. Lock down spare TTYs (same as fresh install)
# ---------------------------------------------------------------------------
log "==> Masking extra TTYs..."
systemctl mask "getty@tty2.service" "getty@tty3.service" "getty@tty4.service" \
               "getty@tty5.service" "getty@tty6.service" 2>/dev/null || true
systemctl mask "autovt@.service" 2>/dev/null || true
systemctl mask "serial-getty@.service" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 9. Conflicting display managers
# ---------------------------------------------------------------------------
OTHER_DMS=(gdm lightdm lxdm)
FOUND_DMS=()
for dm in "${OTHER_DMS[@]}"; do
    pacman -Qi "$dm" &>/dev/null && FOUND_DMS+=("$dm")
done

if [ "${#FOUND_DMS[@]}" -gt 0 ]; then
    echo
    echo "Found other display manager(s) installed: ${FOUND_DMS[*]}"
    echo "These will fight with SDDM's autologin if left enabled."
    read -rp "Disable and remove them now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        for dm in "${FOUND_DMS[@]}"; do
            systemctl disable "$dm" 2>/dev/null || true
            run pacman -Rns --noconfirm "$dm" || warn "Failed to remove $dm — remove it manually if it keeps interfering."
        done
    else
        warn "Left ${FOUND_DMS[*]} installed — make sure only sddm.service is enabled (systemctl disable <other-dm>) before rebooting."
    fi
fi

# ---------------------------------------------------------------------------
# 10. Clean up orphaned dependencies
# ---------------------------------------------------------------------------
log "==> Cleaning up orphaned dependencies..."
mapfile -t ORPHANS < <(pacman -Qtdq 2>/dev/null)
if [ "${#ORPHANS[@]}" -gt 0 ]; then
    run pacman -Rns --noconfirm "${ORPHANS[@]}" || warn "Some orphaned packages couldn't be removed — check $LOG."
else
    log "    nothing to clean up"
fi

echo
echo "=================================================================="
echo " Done. Log: $LOG"
echo " Reboot to land on the PlasmaTV user selector."
echo "=================================================================="
