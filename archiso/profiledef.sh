#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="plasmatv-linux"
iso_label="PLASMATV_$(date +%Y%m)"
iso_publisher="PlasmaTV Linux <https://example.invalid>"
iso_application="PlasmaTV Linux Live/Install medium"
iso_version="$(date +%Y.%m.%d)"
install_dir="plasmatv"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19')
file_permissions=(
  ["/root"]="0:0:750"
  ["/root/install.sh"]="0:0:755"
)
