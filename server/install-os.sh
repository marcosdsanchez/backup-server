#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Minimal Arch Linux Backup Server Installer
# 
# Installs a minimal Arch system for the Restic backup server.
# Uses SFTP for secure backups.
# =============================================================================

echo ">>> Arch Linux Backup Server Installer <<<"

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    echo "Error: config.env not found."
    exit 1
fi

[ -z "${DISK:-}" ] && { echo "Error: DISK not set"; exit 1; }
[ -z "${SSH_PUBKEY:-}" ] && { echo "Error: SSH_PUBKEY not set"; exit 1; }

echo "WARNING: This will ERASE $DISK"
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Partition naming
P=""
[[ "$DISK" =~ (nvme|mmcblk) ]] && P="p"

# =============================================================================
# PARTITIONING & FILESYSTEMS
# =============================================================================
echo "--- Partitioning ---"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8300 "$DISK"
partprobe "$DISK"

mkfs.fat -F32 "${DISK}${P}1"
mkfs.ext4 -F "${DISK}${P}2"

mount "${DISK}${P}2" /mnt
mkdir -p /mnt/boot
mount -o umask=0077 "${DISK}${P}1" /mnt/boot

# =============================================================================
# PRE-INSTALL CONFIGURATION
# =============================================================================
echo "--- Pre-configuring system ---"
mkdir -p /mnt/etc
echo "KEYMAP=${KEYMAP:-us}" > /mnt/etc/vconsole.conf
echo "$HOSTNAME" > /mnt/etc/hostname

# =============================================================================
# INSTALL BASE SYSTEM
# =============================================================================
echo "--- Installing base system ---"
pacstrap -K /mnt base linux-lts linux-firmware intel-ucode \
    networkmanager openssh sudo restic neovim

genfstab -U /mnt >> /mnt/etc/fstab

# Use systemd hooks
sed -i 's/^HOOKS=.*/HOOKS=(systemd autodetect microcode modconf kms sd-vconsole block filesystems fsck)/' /mnt/etc/mkinitcpio.conf

# Copy backup server files
mkdir -p /mnt/opt/backup-server
cp -r "$(dirname "$0")" /mnt/opt/backup-server/server
[ -d "$(dirname "$0")/../client" ] && cp -r "$(dirname "$0")/../client" /mnt/opt/backup-server/

# =============================================================================
# CONFIGURE IN CHROOT
# =============================================================================
arch-chroot /mnt /bin/bash <<EOF
set -e

# Locale & time
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Root password
echo "root:${ROOT_PASS:-changeme}" | chpasswd

# Admin user
if [ -n "${ADMIN_USERNAME:-}" ]; then
    useradd -m -G wheel "$ADMIN_USERNAME"
    [ -n "${ADMIN_PASS:-}" ] && echo "$ADMIN_USERNAME:$ADMIN_PASS" | chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    
    # Authorize SSH key for admin user
    mkdir -p "/home/$ADMIN_USERNAME/.ssh"
    echo "$SSH_PUBKEY" > "/home/$ADMIN_USERNAME/.ssh/authorized_keys"
    chown -R "$ADMIN_USERNAME:$ADMIN_USERNAME" "/home/$ADMIN_USERNAME/.ssh"
    chmod 700 "/home/$ADMIN_USERNAME/.ssh"
    chmod 600 "/home/$ADMIN_USERNAME/.ssh/authorized_keys"
fi

# Backup user (for SFTP)
useradd -m -d /srv/backups -s /bin/bash backup
# Lock password (key based auth only)
passwd -l backup
mkdir -p /srv/backups/.ssh
chmod 700 /srv/backups/.ssh
touch /srv/backups/.ssh/authorized_keys
chmod 600 /srv/backups/.ssh/authorized_keys
chown -R backup:backup /srv/backups/.ssh

# SSH
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
echo -e "PasswordAuthentication no\nPermitRootLogin prohibit-password" > /etc/ssh/sshd_config.d/hardening.conf

# Rebuild initramfs with systemd hooks
mkinitcpio -P

# Systemd-boot
bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch-lts.conf
timeout 3
LOADER

cat > /boot/loader/entries/arch-lts.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img
initrd  /initramfs-linux-lts.img
options root=UUID=$(blkid -s UUID -o value ${DISK}${P}2) rw
ENTRY

# Backup directory
mkdir -p /srv/backups && chmod 750 /srv/backups

# Enable services
systemctl enable NetworkManager sshd

# Make helper scripts executable
chmod +x /opt/backup-server/server/*.sh
EOF

umount -R /mnt

echo ""
echo "✅ Done! Reboot, then SSH in and run:"
echo "   cat /opt/backup-server/README.md"
