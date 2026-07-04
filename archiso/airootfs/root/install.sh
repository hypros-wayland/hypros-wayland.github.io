#!/usr/bin/env bash
# PlasmaTV Linux installer — runs as root on the archiso live system.
# Auto-launched by the getty@tty1.service.d/autologin.conf override.
set -uo pipefail

BACKTITLE="PlasmaTV Linux Installer"
LOG=/tmp/plasmatv-install.log
: > "$LOG"

d() { dialog --backtitle "$BACKTITLE" "$@"; }

die() {
    d --title "Error" --msgbox "$1\n\nSee $LOG for details." 12 60
    clear
    exit 1
}

run() {
    # run a command, streaming to the log, aborting the installer on failure
    echo "+ $*" >> "$LOG"
    if ! "$@" >> "$LOG" 2>&1; then
        die "Command failed: $*"
    fi
}

progress() {
    # Update a --gauge's percentage AND message text. dialog's gauge
    # protocol only updates the message if you wrap it in XXX markers —
    # a bare "echo 10; echo '# text'" (what this used to do) only ever
    # moves the bar and silently ignores the text, which is why the
    # dialog used to just sit on "Starting..." the whole time.
    echo "XXX"
    echo "$1"
    echo "$2"
    echo "XXX"
}

# ---------------------------------------------------------------------------
# 1. Welcome
# ---------------------------------------------------------------------------
d --title "Welcome" --yesno \
"Welcome to the PlasmaTV Linux installer.\n\n\
This will ERASE a disk of your choosing and install PlasmaTV Linux\n\
(Arch + Plasma Bigscreen + Plasma Desktop).\n\n\
Continue?" 12 70 || { clear; exit 0; }

# ---------------------------------------------------------------------------
# 2. Network setup
# ---------------------------------------------------------------------------
# archiso runs systemd-networkd by default, which conflicts with NM.
# Shut it down and let NM take over completely.
systemctl stop systemd-networkd 2>/dev/null || true
systemctl stop systemd-resolved 2>/dev/null || true
systemctl enable --now NetworkManager 2>/dev/null || true
nmcli general networking on 2>/dev/null || true
sleep 3

# Collect all non-loopback interfaces
IFACES=()
for iface in /sys/class/net/*; do
    name=$(basename "$iface")
    [ "$name" = "lo" ] && continue
    IFACES+=("$name")
done

WIRED_IFACE=""
for name in "${IFACES[@]}"; do
    carrier="$(cat /sys/class/net/"$name"/carrier 2>/dev/null)"
    if [ "$carrier" = "1" ]; then
        WIRED_IFACE="$name"
        break
    fi
done

net_ok=0

if [ -n "$WIRED_IFACE" ]; then
    d --title "Network" --infobox "Wired link detected on $WIRED_IFACE — connecting..." 6 65
    nmcli device connect "$WIRED_IFACE" 2>/dev/null || true
    nmcli device set "$WIRED_IFACE" autoconnect yes 2>/dev/null || true
    for _ in $(seq 1 20); do
        nmcli -t -f DEVICE,STATE dev status 2>/dev/null | grep -q "^$WIRED_IFACE:connected" && { net_ok=1; break; }
        sleep 1
    done
    if [ "$net_ok" = "0" ]; then
        # Fallback: dhcpcd directly
        dhcpcd "$WIRED_IFACE" >/dev/null 2>&1 &
        for _ in $(seq 1 10); do
            ip -4 addr show "$WIRED_IFACE" 2>/dev/null | grep -q 'inet ' && { net_ok=1; break; }
            sleep 1
        done
    fi
fi

# Wi‑Fi fallback if wired failed
if [ "$net_ok" = "0" ]; then
    WLAN_IFACE=""
    for name in "${IFACES[@]}"; do
        [ -d "/sys/class/net/$name/wireless" ] && { WLAN_IFACE="$name"; break; }
    done
    if [ -z "$WLAN_IFACE" ]; then
        # Try nmcli as fallback (some virtual Wi-Fi adapters)
        WLAN_IFACE=$(nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
    fi

    if [ -n "$WLAN_IFACE" ]; then
        d --title "Network" --infobox "No wired link — scanning Wi-Fi on $WLAN_IFACE..." 6 65
        nmcli radio wifi on 2>/dev/null || true
        ip link set "$WLAN_IFACE" up 2>/dev/null || true
        nmcli dev wifi rescan ifname "$WLAN_IFACE" 2>/dev/null || true
        sleep 5
        mapfile -t WIFI_RAW < <(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname "$WLAN_IFACE" 2>/dev/null \
            | awk -F: '$1!=""' | sort -t: -k2 -rn | awk -F: '!seen[$1]++')
        if [ "${#WIFI_RAW[@]}" -eq 0 ]; then
            d --title "Wi-Fi" --msgbox "No Wi-Fi networks found.\n\nOptions:\n- Check Wi-Fi is enabled\n- Move closer to the router\n- Use tty2 (Ctrl+Alt+F2) to debug manually:\n    nmcli dev wifi list\n    nmcli dev wifi connect <SSID> password <pass>\n  Then switch back (Ctrl+Alt+F1) and re-run /root/install.sh" 14 70
        else
            WIFI_ITEMS=()
            for line in "${WIFI_RAW[@]}"; do
                ssid="${line%%:*}"
                rest="${line#*:}"
                signal="${rest%%:*}"
                WIFI_ITEMS+=("$ssid" "${signal}%")
            done
            SSID=$(d --title "Wi-Fi" --menu "Choose a network:" 18 70 8 "${WIFI_ITEMS[@]}" 3>&1 1>&2 2>&3)
            if [ -n "${SSID:-}" ]; then
                WIFIPASS=$(d --title "Wi-Fi password" --insecure --passwordbox "Password for $SSID:" 8 65 3>&1 1>&2 2>&3) || WIFIPASS=""
                d --title "Wi-Fi" --infobox "Connecting to $SSID..." 5 50
                nmcli dev wifi connect "$SSID" password "$WIFIPASS" ifname "$WLAN_IFACE" 2>/dev/null || true
                for _ in $(seq 1 15); do
                    nmcli -t -f DEVICE,STATE dev status 2>/dev/null | grep -q "^$WLAN_IFACE:connected" && { net_ok=1; break; }
                    sleep 1
                done
                if [ "$net_ok" = "0" ]; then
                    # Fallback: wpa_supplicant + dhcpcd
                    wpa_passphrase "$SSID" "$WIFIPASS" > /tmp/wpa.conf 2>/dev/null
                    wpa_supplicant -B -i "$WLAN_IFACE" -c /tmp/wpa.conf 2>/dev/null || true
                    dhcpcd "$WLAN_IFACE" >/dev/null 2>&1 &
                    for _ in $(seq 1 10); do
                        ip -4 addr show "$WLAN_IFACE" 2>/dev/null | grep -q 'inet ' && { net_ok=1; break; }
                        sleep 1
                    done
                fi
            fi
        fi
    else
        d --title "Network" --msgbox "No ethernet link and no Wi-Fi device found.\n\nPlug in a cable or Wi-Fi adapter, then re-run:\n/root/install.sh" 10 65
    fi
fi

# Final check — try IP first, then DNS
if [ "$net_ok" = "1" ]; then
    # Wait for DNS to propagate
    sleep 2
    # Ping by IP first (Cloudflare DNS) to bypass DNS resolution issues
    if ! timeout 6 ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        net_ok=0
    fi
fi

if [ "$net_ok" = "0" ]; then
    d --title "Network" --msgbox \
"Still no network connection.\n\n\
Options:\n\
  1. Check your cable / Wi-Fi\n\
  2. Switch to tty2 (Ctrl+Alt+F2) and troubleshoot:\n\
     ip link\n\
     nmcli dev status\n\
     nmcli dev wifi connect <SSID> password <pass>\n\
  3. Switch back (Ctrl+Alt+F1) and re-run:\n\
     /root/install.sh\n\
  4. Try a different network adapter" 16 70
    clear
    exit 1
fi

# ---------------------------------------------------------------------------
# 2b. Virtualization detection (VMware -> open-vm-tools)
# ---------------------------------------------------------------------------
# Also timeout-bounded — systemd-detect-virt should be instant, but
# there's no reason to let anything in this script block forever. Falls
# back to "none" (skip VM tooling) rather than hang the installer.
VIRT=$(timeout 5 systemd-detect-virt 2>/dev/null || echo none)
EXTRA_PKGS=()
if [ "$VIRT" = "vmware" ]; then
    d --title "VMware detected" --msgbox \
"This looks like a VMware virtual machine.\n\nopen-vm-tools will be\ninstalled and enabled automatically for better integration\n(shared clipboard, resolution sync, etc)." 10 60
    EXTRA_PKGS+=(open-vm-tools)
fi

# ---------------------------------------------------------------------------
# 2c. Firmware detection: BIOS / IA32 (32-bit) UEFI / 64-bit UEFI
# ---------------------------------------------------------------------------
if [ -d /sys/firmware/efi ]; then
    FW_BITS=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo 64)
    if [ "$FW_BITS" = "32" ]; then
        FIRMWARE="uefi32"
        FW_LABEL="32-bit (IA32) UEFI"
    else
        FIRMWARE="uefi64"
        FW_LABEL="64-bit UEFI"
    fi
else
    FIRMWARE="bios"
    FW_LABEL="legacy BIOS"
fi

# ---------------------------------------------------------------------------
# 2d. Partition table choice
#   - UEFI (either bitness): always GPT (required for a standards-compliant ESP)
#   - BIOS: GPT+bios_grub (recommended, no size/4-primary-partition limits)
#           or classic MBR, for very old firmware that chokes on GPT
# ---------------------------------------------------------------------------
PARTTABLE="gpt"
if [ "$FIRMWARE" = "bios" ]; then
    PARTTABLE=$(d --title "Partition table" --menu \
"Detected: $FW_LABEL\n\nWhich partition table should the target disk use?" 14 70 2 \
"gpt" "GPT with a BIOS boot partition (recommended)" \
"mbr" "Classic MBR (only if your BIOS can't handle GPT)" \
3>&1 1>&2 2>&3) || { clear; exit 0; }
else
    d --title "Firmware detected" --msgbox "Detected: $FW_LABEL\n\nUsing a GPT partition table with an EFI System Partition." 9 60
fi

# ---------------------------------------------------------------------------
# 3. Disk selection
# ---------------------------------------------------------------------------
mapfile -t DISK_LINES < <(lsblk -dpno NAME,SIZE,MODEL | grep -E '^/dev/(sd|nvme|vd)')
[ "${#DISK_LINES[@]}" -eq 0 ] && die "No suitable disks found."

MENU_ITEMS=()
for line in "${DISK_LINES[@]}"; do
    name=$(awk '{print $1}' <<< "$line")
    rest=$(cut -d' ' -f2- <<< "$line")
    MENU_ITEMS+=("$name" "$rest")
done

DISK=$(d --title "Select Disk" --menu \
"Choose the disk to install PlasmaTV Linux on.\nEVERYTHING on it will be erased." \
18 70 8 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3) || { clear; exit 0; }

d --title "Confirm" --yesno \
"This will COMPLETELY ERASE:\n\n  $DISK\n\nAre you absolutely sure?" 10 60 \
|| { clear; exit 0; }

# ---------------------------------------------------------------------------
# 4. Hostname / user setup
# ---------------------------------------------------------------------------
HOSTNAME=$(d --title "Hostname" --inputbox "System hostname:" 8 50 "plasmatv" 3>&1 1>&2 2>&3) || exit 0
[ -z "$HOSTNAME" ] && HOSTNAME="plasmatv"

d --title "TV user" --msgbox \
"A regular user 'tv-user' will be created and set to auto-login into\nPlasma Bigscreen.\n\nroot's password will be set during install, then LOCKED\n(passwd -l) — no direct root login, console or otherwise." 12 65

TVPASS=$(d --title "tv-user password" --inputbox \
"Password for tv-user (used for sudo, not for auto-login):" 8 60 "foobar" 3>&1 1>&2 2>&3) || exit 0
[ -z "$TVPASS" ] && TVPASS="foobar"

# ---------------------------------------------------------------------------
# 5. Partition & format
# ---------------------------------------------------------------------------
{
progress 5 "Wiping partition table on $DISK"
run wipefs -af "$DISK"

ESP=""
BIOSGRUB=""

if [ "$FIRMWARE" != "bios" ] || [ "$PARTTABLE" = "gpt" ]; then
    # GPT, in every case except "BIOS + user explicitly chose MBR"
    run sgdisk -Zo "$DISK"

    if [ "$FIRMWARE" = "bios" ]; then
        progress 15 "Creating GPT + BIOS boot partition"
        run sgdisk -n1:0:+1M   -t1:ef02 -c1:BIOSGRUB "$DISK"
        run sgdisk -n2:0:0     -t2:8300 -c2:PLASMATVROOT "$DISK"
        run partprobe "$DISK"
        sleep 2
        if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
            BIOSGRUB="${DISK}p1"; ROOT="${DISK}p2"
        else
            BIOSGRUB="${DISK}1"; ROOT="${DISK}2"
        fi
    else
        progress 15 "Creating GPT + EFI System Partition"
        run sgdisk -n1:0:+512M -t1:ef00 -c1:PLASMATVESP "$DISK"
        run sgdisk -n2:0:0     -t2:8300 -c2:PLASMATVROOT "$DISK"
        run partprobe "$DISK"
        sleep 2
        if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
            ESP="${DISK}p1"; ROOT="${DISK}p2"
        else
            ESP="${DISK}1"; ROOT="${DISK}2"
        fi
    fi
else
    # BIOS + classic MBR
    progress 15 "Creating MBR partition table"
    run parted -s "$DISK" mklabel msdos
    run parted -s "$DISK" mkpart primary ext4 1MiB 100%
    run parted -s "$DISK" set 1 boot on
    run partprobe "$DISK"
    sleep 2
    if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
        ROOT="${DISK}p1"
    else
        ROOT="${DISK}1"
    fi
fi

progress 30 "Formatting partitions"
# ESP FAT label max length is 11 chars (FAT 8.3 constraint) — PLASMATVESP is exactly 11.
[ -n "$ESP" ] && run mkfs.fat -F32 -n PLASMATVESP "$ESP"
run mkfs.ext4 -F -L plasmatv_root "$ROOT"
# bios_grub partition is never formatted — grub-install embeds core.img directly into it.

progress 40 "Mounting filesystems"
run mount "$ROOT" /mnt
if [ -n "$ESP" ]; then
    run mkdir -p /mnt/boot
    run mount "$ESP" /mnt/boot
fi

progress 43 "Initializing pacman keyring"
run pacman-key --init
run pacman-key --populate archlinux

progress 45 "Installing base system — this is the long step, hang tight"
run pacstrap -K /mnt $(grep -vE '^\s*#|^\s*$' /root/packages.x86_64 2>/dev/null || cat <<'PKGS'
base linux linux-firmware sudo nano vim dialog git networkmanager
grub efibootmgr os-prober plymouth dosfstools binutils
plasma-desktop plasma-bigscreen sddm
konsole dolphin kde-cli-tools xdg-desktop-portal xdg-desktop-portal-kde
pipewire pipewire-pulse wireplumber bluez bluez-utils noto-fonts ttf-liberation
PKGS
) "${EXTRA_PKGS[@]}"

progress 85 "Generating fstab"
run bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

progress 92 "Copying PlasmaTV files onto the target"
run cp -a /root/skel/. /mnt/

progress 100 "Base install done"
sleep 1
} | d --title "Installing" --gauge "Starting..." 12 70 0

# ---------------------------------------------------------------------------
# 6. Chroot configuration
# ---------------------------------------------------------------------------
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")

cat > /mnt/root/chroot-setup.sh << CHROOT
set -e
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# root: set a password only so it exists as a stored hash, then LOCK it —
# no interactive root login anywhere (console, autologin, or otherwise).
# tv-user still has full sudo via the wheel group for anything that needs it.
echo "root:foobar" | chpasswd
passwd -l root

# tv-user
useradd -m -G wheel,video,audio,input -s /bin/bash tv-user
echo "tv-user:$TVPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# selector-user: kiosk-only account, SDDM always lands here between real
# user sessions (see /usr/share/wayland-sessions/plasmatv-selector.desktop
# and plasmatv-login-as / plasmatv-return-to-selector).
useradd -m -s /usr/sbin/nologin selector-user
passwd -l selector-user >/dev/null

# PlasmaTV config store
mkdir -p /etc/plasmatv
[ -f /etc/plasmatv/users-secrets.json ] || echo '{}' > /etc/plasmatv/users-secrets.json
chmod 600 /etc/plasmatv/users-secrets.json
chmod 644 /etc/plasmatv/users-public.json

mkdir -p /var/lib/plasmatv/screentime

# tv-user gets the return-to-selector hook wired into its user session too
install -d -m755 /home/tv-user/.config/systemd/user/graphical-session.target.wants
ln -sf /etc/plasmatv/skel-user-units/plasmatv-return-to-selector.service \
  /home/tv-user/.config/systemd/user/graphical-session.target.wants/plasmatv-return-to-selector.service
chown -R tv-user:tv-user /home/tv-user/.config

# minimal locked-down PATH for child-user-* rbash sessions
mkdir -p /usr/local/lib/plasmatv-child-bin
rm -f /usr/local/lib/plasmatv-child-bin/.gitkeep
ln -sf "\$(command -v electron || echo /usr/bin/electron)" /usr/local/lib/plasmatv-child-bin/electron

# SDDM autologin already ships pointed at selector-user/plasmatv-selector.desktop
# (see skel/etc/sddm.conf.d/autologin.conf) — nothing to rewrite here.

# lock down spare TTYs: no login prompt reachable except through SDDM/autologin
systemctl mask "getty@tty2.service" "getty@tty3.service" "getty@tty4.service" \
               "getty@tty5.service" "getty@tty6.service" || true
systemctl mask "autovt@.service" || true
systemctl mask "serial-getty@.service" || true

# mkinitcpio: add plymouth hook
sed -i 's/^HOOKS=(base udev autodetect/HOOKS=(base udev plymouth autodetect/' /etc/mkinitcpio.conf

# plymouth theme (stock "spinner" theme, ships with the plymouth package)
plymouth-set-default-theme -R spinner || true

# --- bootloader: differs by firmware -------------------------------------
FIRMWARE="$FIRMWARE"
if [ "\$FIRMWARE" = "uefi64" ]; then
    # 64-bit UEFI: no GRUB at all. Build a Unified Kernel Image and
    # register it directly as an EFI boot entry named "System0" — the
    # firmware boots it with no bootloader/menu layer in between.
    echo "root=UUID=$ROOT_UUID rw quiet splash" > /etc/kernel/cmdline
    mkdir -p /boot/EFI/Linux
    cat > /etc/mkinitcpio.d/linux.preset << 'PRESET'
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/EFI/Linux/plasmatv.efi"
default_options="--cmdline /etc/kernel/cmdline"
PRESET
    mkinitcpio -p linux

    ESP_PARTNUM=1
    efibootmgr --create --disk "$DISK" --part "\$ESP_PARTNUM" \
      --loader '\EFI\Linux\plasmatv.efi' --label "System0"
    BOOTNUM=\$(efibootmgr | awk '/System0/ {print substr(\$1,5,4); exit}')
    [ -n "\$BOOTNUM" ] && efibootmgr --bootorder "\$BOOTNUM" || true
    # NOTE: this UKI is unsigned. If Secure Boot is enabled in firmware
    # setup, either disable it or sign the UKI yourself (sbsigntools) —
    # out of scope for this installer.
else
    mkinitcpio -P

    if [ "\$FIRMWARE" = "bios" ]; then
        grub-install --target=i386-pc "$DISK"
    else
        # uefi32 / IA32 UEFI
        grub-install --target=i386-efi --efi-directory=/boot \
          --bootloader-id=PlasmaTV --removable
    fi

    # Single static "System0" entry, instant boot — deliberately NOT using
    # grub-mkconfig here, since its os-prober-driven template can't cleanly
    # produce "exactly one entry named System0, timeout 0" and would need
    # to be re-forced after every kernel update anyway.
    mkdir -p /boot/grub
    cat > /boot/grub/grub.cfg << GRUBCFG
set timeout=0
set default=0

insmod part_gpt
insmod part_msdos
insmod ext2

menuentry "System0" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-linux root=UUID=$ROOT_UUID rw quiet splash
    initrd /boot/initramfs-linux.img
}
GRUBCFG
fi

# services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth || true
systemctl enable tv-oobe.service || true
systemctl enable plasmatv-dns-rules.service || true
systemctl enable plasmatv-timelimit-daemon.service || true

if [ "$VIRT" = "vmware" ]; then
    systemctl enable vmtoolsd.service || true
    systemctl enable vmware-vmblock-fuse.service || true
fi

# mark first boot for the TV OOBE wizard
touch /etc/plasmatv-first-boot
CHROOT
chmod +x /mnt/root/chroot-setup.sh

d --title "Configuring" --infobox "Configuring bootloader, users, and services..." 6 60
if ! arch-chroot /mnt /root/chroot-setup.sh >> "$LOG" 2>&1; then
    die "chroot configuration failed"
fi
rm -f /mnt/root/chroot-setup.sh

d --title "Done" --msgbox \
"PlasmaTV Linux is installed ($FW_LABEL, $PARTTABLE).\n\n\
Login: tv-user / (the password you chose)\n\
root login is locked (console and otherwise).\n\n\
Remove the install media and reboot." 13 65

clear
