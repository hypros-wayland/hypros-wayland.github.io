#!/usr/bin/env bash
# optional/enable-selinux.sh
#
# NOT run automatically by install.sh or transform-existing-system.sh.
# SELinux is NOT officially supported on Arch Linux. This script uses the
# unofficial, UNSIGNED third-party repo maintained at
# https://github.com/archlinuxhardened/selinux, which replaces core
# system packages (coreutils, systemd, dbus, shadow, openssh, findutils,
# iproute2, logrotate, cronie) with SELinux-patched forks. As of this
# writing there are open, unresolved compatibility issues in that project
# (e.g. systemd-selinux failing to build against current libxml2), and
# the ArchWiki itself warns the reference policy isn't well maintained
# for Arch compatibility.
#
# Read that as: this can break your system. Test in a VM/snapshot first.
# This script installs SELinux in PERMISSIVE mode (logs denials, blocks
# nothing) rather than enforcing, specifically so a bad policy interaction
# doesn't lock you out — flipping to enforcing is a manual, deliberate
# step described at the bottom of this file.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }

cat << 'EOF'
==================================================================
 PlasmaTV Linux — optional SELinux enablement (UNOFFICIAL, RISKY)
==================================================================
This adds an unsigned third-party pacman repo and replaces several
core system packages with SELinux-patched forks. It is NOT part of
the normal PlasmaTV Linux install and is NOT recommended for the
TV appliance itself — this exists for people who specifically want
to experiment with SELinux on an Arch box.

Known risks:
  - Unsigned repo (SigLevel = Never) — you are trusting
    archlinuxhardened/selinux's binaries directly.
  - Replaces coreutils, systemd, dbus, shadow, and others with
    forks that have had real build/compat breakage recently.
  - The reference policy is not well maintained for Arch — expect
    to spend time debugging denials and mislabeled files.
  - This script leaves SELinux in PERMISSIVE mode. Read the
    printed instructions at the end before ever switching to
    enforcing mode.

Source: https://github.com/archlinuxhardened/selinux
==================================================================
EOF
read -rp "Type 'yes-i-understand-the-risk' to continue: " confirm
[ "$confirm" = "yes-i-understand-the-risk" ] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# 1. Add the unofficial, unsigned SELinux repo
# ---------------------------------------------------------------------------
if ! grep -q '^\[selinux\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf << 'EOF'

[selinux]
Server = https://github.com/archlinuxhardened/selinux/releases/download/ArchLinux-SELinux
SigLevel = Never
EOF
    echo "Added [selinux] repo to /etc/pacman.conf"
else
    echo "[selinux] repo already present in /etc/pacman.conf"
fi

pacman -Sy

# ---------------------------------------------------------------------------
# 2. Base SELinux userspace + libraries (does not replace your kernel —
#    mainline Arch kernels have had SELinux LSM support built in since
#    ~2014, it just isn't enabled at boot until you add the lsm= param
#    below)
# ---------------------------------------------------------------------------
pacman -S --needed --noconfirm base-selinux policycoreutils-selinux \
    libselinux libsepol libsemanage checkpolicy || {
    echo "Package install failed. This repo is known to have broken"
    echo "packages from time to time — check"
    echo "https://github.com/archlinuxhardened/selinux/issues"
    exit 1
}

echo
echo "Skipping the *-selinux forks of coreutils/systemd/dbus/shadow/etc"
echo "by default — these are the packages most likely to break your"
echo "boot. Install them yourself, one at a time, only if you actually"
echo "need them:"
echo "  pacman -S coreutils-selinux systemd-selinux dbus-selinux \\"
echo "            shadow-selinux openssh-selinux findutils-selinux"

# ---------------------------------------------------------------------------
# 3. Reference policy — ArchWiki: "not very good for Arch Linux", must be
#    built from source. Not automated here; see instructions below.
# ---------------------------------------------------------------------------
mkdir -p /etc/selinux
if [ ! -d /etc/selinux/refpolicy ]; then
    echo
    echo "Reference policy is NOT built automatically by this script —"
    echo "the ArchWiki explicitly warns it needs manual attention per"
    echo "package. Build it yourself as a non-root user:"
    echo
    echo "  useradd -m builder   # if you don't already have a build user"
    echo "  su - builder"
    echo "  git clone https://aur.archlinux.org/selinux-refpolicy-src.git"
    echo "  cd selinux-refpolicy-src && makepkg -si"
    echo
fi

# ---------------------------------------------------------------------------
# 4. /etc/selinux/config — permissive, not enforcing
# ---------------------------------------------------------------------------
cat > /etc/selinux/config << 'EOF'
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#   enforcing  - SELinux security policy is enforced.
#   permissive - SELinux prints warnings instead of enforcing.
#   disabled   - No SELinux policy is loaded.
SELINUX=permissive
SELINUXTYPE=refpolicy
EOF

echo
echo "=================================================================="
echo " Done (permissive mode)."
echo
echo " Remaining manual steps:"
echo " 1. Build the reference policy (see above) — nothing is enforced"
echo "    or even labeled until a policy is loaded."
echo " 2. Add 'lsm=landlock,lockdown,yama,integrity,selinux,bpf' (or"
echo "    append 'selinux' to your existing lsm= list) to"
echo "    GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then:"
echo "      grub-mkconfig -o /boot/grub/grub.cfg"
echo " 3. Reboot, then relabel the filesystem:"
echo "      touch /.autorelabel && reboot"
echo " 4. Watch 'journalctl' / 'ausearch' for denials while permissive"
echo "    before ever setting SELINUX=enforcing in /etc/selinux/config."
echo "=================================================================="
