#!/usr/bin/env bash
# Build PlasmaTV Linux ISOs.
#   bash build.sh              — build both full and netinstall
#   bash build.sh full         — full only
#   bash build.sh netinstall   — netinstall only
# Run as root (or with sudo) on an Arch (or Arch-based) build machine
# with the `archiso` package installed.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v mkarchiso >/dev/null; then
    echo "mkarchiso not found — install the 'archiso' package first." >&2
    exit 1
fi

build_full() {
    echo "=== Building FULL ISO ==="
    # Drop the package list into airootfs/root so install.sh can read it
    # for the target-system pacstrap too.
    cp archiso/packages.x86_64 archiso/airootfs/root/packages.x86_64

    # Copy the skel/ tree (target-system files) into the live root so the
    # installer can `cp -a /root/skel/. /mnt/` at install time.
    rm -rf archiso/airootfs/root/skel
    cp -a skel archiso/airootfs/root/skel

    # Use the default install.sh
    rm -f archiso/airootfs/root/install-netinstall.sh

    mkdir -p out work-full
    mkarchiso -v -w work-full -o out archiso

    # Rename to full ISO
    mv out/plasmatv-linux-*.iso out/plasmatv-linux-full-$(date +%Y.%m.%d)-x86_64.iso 2>/dev/null || true
    echo "=== FULL ISO done ==="
}

build_netinstall() {
    echo "=== Building NETINSTALL ISO ==="
    # Use the minimal package list for the live environment
    cp archiso/packages.netinstall.x86_64 archiso/packages.x86_64

    # Use the netinstall installer variant
    cp archiso/airootfs/root/install-netinstall.sh archiso/airootfs/root/install.sh

    # Don't include packages.x86_64 or skel/ — they're downloaded from GitHub
    rm -f archiso/airootfs/root/packages.x86_64
    rm -rf archiso/airootfs/root/skel

    mkdir -p out work-netinstall
    mkarchiso -v -w work-netinstall -o out archiso

    # Rename to netinstall ISO
    mv out/plasmatv-linux-*.iso out/plasmatv-linux-netinstall-$(date +%Y.%m.%d)-x86_64.iso 2>/dev/null || true

    # Restore the full install.sh
    git checkout archiso/airootfs/root/install.sh 2>/dev/null || true
    git checkout archiso/packages.x86_64 2>/dev/null || true
    rm -f archiso/airootfs/root/install-netinstall.sh
    echo "=== NETINSTALL ISO done ==="
}

WHAT="${1:-both}"
case "$WHAT" in
    full)       build_full ;;
    netinstall) build_netinstall ;;
    both)
        build_full
        # Restore files before netinstall build
        git checkout archiso/airootfs/root/install.sh archiso/packages.x86_64 2>/dev/null || true
        rm -f archiso/airootfs/root/packages.x86_64
        rm -rf archiso/airootfs/root/skel
        build_netinstall
        ;;
    *)          echo "Usage: $0 [full|netinstall|both]"; exit 1 ;;
esac

echo
echo "Done. ISOs are in out/:"
ls -lh out/
