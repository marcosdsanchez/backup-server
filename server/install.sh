#!/usr/bin/env bash
set -euo pipefail

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    echo "Error: config.env not found."
    exit 1
fi

if [ -z "$SSH_PUBKEY" ]; then
    echo "Error: SSH_PUBKEY is not set in config.env. Required for headless setup."
    exit 1
fi

echo ">>> Arch Linux Backup Server Installer <<<"
echo "Assumptions: Ethernet connection (DHCP), $DISK will be WIPED."

### 1. TIME SETUP
echo "Configuring time..."
timedatectl set-ntp true

### 2. PARTITIONING
echo "Partitioning $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 -c 1:EFI "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:cryptroot "$DISK"
partprobe "$DISK"

### 3. FILESYSTEMS & ENCRYPTION
echo "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"

echo "Setting up LUKS encryption..."
cryptsetup luksFormat "${DISK}2"
cryptsetup open "${DISK}2" "$CRYPT_NAME"

mkfs.ext4 "/dev/mapper/$CRYPT_NAME"

### 4. MOUNTING
echo "Mounting filesystems..."
mount "/dev/mapper/$CRYPT_NAME" /mnt
mkdir /mnt/efi
mount "${DISK}1" /mnt/efi

### 5. PACKAGE INSTALLATION
echo "Installing base system (LTS kernel)..."
pacstrap /mnt \
  base linux-lts linux-firmware \
  openssh sudo restic neovim \
  dropbear mkinitcpio-netconf

genfstab -U /mnt >> /mnt/etc/fstab

### 6. SYSTEM CONFIGURATION (CHROOT)
# Prompt for passwords before entering chroot to avoid stdin redirection issues
echo "--- User Configuration ---"
if [ -n "$ADMIN_USERNAME" ]; then
    while true; do
        read -s -p "Enter password for $ADMIN_USERNAME: " ADMIN_PASS
        echo ""
        read -s -p "Confirm password for $ADMIN_USERNAME: " ADMIN_PASS_CONFIRM
        echo ""
        [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ] && break
        echo "Passwords do not match. Try again."
    done
fi

while true; do
    read -s -p "Enter password for root: " ROOT_PASS
    echo ""
    read -s -p "Confirm password for root: " ROOT_PASS_CONFIRM
    echo ""
    [ "$ROOT_PASS" = "$ROOT_PASS_CONFIRM" ] && break
    echo "Passwords do not match. Try again."
done

echo "Entering chroot to configure system..."
arch-chroot /mnt /bin/bash <<EOF
set -e

echo "$HOSTNAME" > /etc/hostname

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

### --- USERS & SSH ---
# Set root password
chpasswd <<< "root:$ROOT_PASS"
unset ROOT_PASS
unset ROOT_PASS_CONFIRM

# If ADMIN_USERNAME is provided, create a sudo user
if [ -n "$ADMIN_USERNAME" ]; then
    useradd -m -G wheel "$ADMIN_USERNAME"
    chpasswd <<< "$ADMIN_USERNAME:$ADMIN_PASS"
    unset ADMIN_PASS
    unset ADMIN_PASS_CONFIRM
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

# SSH Setup
mkdir -p /root/.ssh
echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

systemctl enable sshd

### --- NETWORK ---
# Enable systemd-networkd and systemd-resolved
systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Robustly create the resolv.conf symlink
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || echo "Warning: Could not create resolv.conf symlink, might be a bind mount"

# Create a default DHCP network configuration for ethernet
cat <<NET > /etc/systemd/network/20-wired.network
[Match]
Name=e*

[Network]
DHCP=yes
NET

### --- BACKUP USER ---
mkdir /backups
useradd --system --home /backups --shell /usr/bin/nologin backup
chown backup:backup /backups
chmod 750 /backups

mkdir /backups/.ssh
touch /backups/.ssh/authorized_keys
chown -R backup:backup /backups/.ssh
chmod 700 /backups/.ssh
chmod 600 /backups/.ssh/authorized_keys

### 7. BOOTLOADER & INITRAMFS (Remote Unlock)
echo "Configuring remote unlock..."
mkdir -p /etc/dropbear
echo "$SSH_PUBKEY" > /etc/dropbear/root_key
chmod 600 /etc/dropbear/root_key

# Add encrypt, net and dropbear to HOOKS
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf keyboard block encrypt net dropbear filesystems fsck)/' /etc/mkinitcpio.conf

ROOT_UUID=\$(blkid -s UUID -o value ${DISK}2)

bootctl install

cat > /boot/loader/entries/arch.conf <<BOOT
title   Arch Linux (LTS)
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options cryptdevice=UUID=\$ROOT_UUID:$CRYPT_NAME root=/dev/mapper/$CRYPT_NAME rw ip=dhcp
BOOT

mkinitcpio -P
EOF

echo "✅ Install complete"
echo "➡️ Reboot the server"
echo "➡️ SSH into initramfs to unlock disk:"
echo "   ssh root@<server-ip>"
echo "   cryptroot-unlock"
echo "➡️ After unlock, SSH into the system as root or $ADMIN_USERNAME"
