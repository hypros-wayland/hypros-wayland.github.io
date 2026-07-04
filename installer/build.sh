#!/usr/bin/env bash
# Build the PlasmaTV Linux ISO from the archiso/ profile.
# Run as root (or with sudo) on an Arch (or Arch-based) build machine
# with the `archiso` package installed.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v mkarchiso >/dev/null; then
    echo "mkarchiso not found — install the 'archiso' package first." >&2
    exit 1
fi

# Drop the package list into airootfs/root so install.sh can read it
# for the target-system pacstrap too.
cp archiso/packages.x86_64 archiso/airootfs/root/packages.x86_64

# Copy the skel/ tree (target-system files) into the live root so the
# installer can `cp -a /root/skel/. /mnt/` at install time.
rm -rf archiso/airootfs/root/skel
cp -a skel archiso/airootfs/root/skel

mkdir -p out work
mkarchiso -v -w work -o out archiso

echo
echo "Done. ISO is in out/"
