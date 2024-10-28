#!/bin/bash

# Function to display a menu and get user choice
menu() {
local prompt="$1"
shift
local options=("$@")
local choice
PS3="$prompt"
select choice in "${options[@]}"; do
if [[ -n "$choice" ]]; then
echo "$choice"
break
else
echo "Invalid choice. Please try again."
fi
done
}

# Function to get user input
get_input() {
local prompt="$1"
read -rp "$prompt: " input
echo "$input"
}

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
echo "dialog could not be found, installing..."
sudo pacman -S --noconfirm dialog
fi

# Ask for text editor
text_editor=$(menu "Choose your text editor:" "nano" "vim")

# Ask for bootloader
bootloader=$(menu "Choose your bootloader:" "grub" "systemd-boot")

# Ask for username
username=$(get_input "Enter your username")

# Ask for password
password=$(get_input "Enter your password")

# Ask for disk to install on
disk=$(lsblk -dpno NAME | menu "Choose the disk to install Arch Linux on:" $(lsblk -dpno NAME))

# Ask if using UEFI
uefi=$(menu "Are you using UEFI?" "Yes" "No")

# Ask for region
region=$(get_input "Enter your region (e.g., America, Europe, Asia)")

# Ask for city
city=$(get_input "Enter your city (e.g., New_York, London, Tokyo)")

# Partition the disk
echo "Partitioning the disk..."
if [[ "$uefi" == "Yes" ]]; then
parted "$disk" mklabel gpt
parted "$disk" mkpart primary fat32 1MiB 512MiB
parted "$disk" set 1 esp on
parted "$disk" mkpart primary ext4 512MiB 100%
mkfs.fat -F32 "${disk}1"
mkfs.ext4 "${disk}2"
mount "${disk}2" /mnt
mkdir -p /mnt/boot/efi
mount "${disk}1" /mnt/boot/efi
else
parted "$disk" mklabel msdos
parted "$disk" mkpart primary ext4 1MiB 100%
mkfs.ext4 "${disk}1"
mount "${disk}1" /mnt
fi

# Install the base system
echo "Installing the base system..."
pacstrap /mnt base linux linux-firmware base-devel

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt <<EOF

# Set the time zone
ln -sf /usr/share/zoneinfo/$region/$city /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "archlinux" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOT

# Install bootloader
if [[ "$bootloader" == "grub" ]]; then
pacman -S grub --noconfirm
if [[ "$uefi" == "Yes" ]]; then
pacman -S efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
else
bootctl install
cat <<EOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "${disk}1") rw
EOT
fi

# Create a user
useradd -m -G wheel -s /bin/bash $username
echo "$username:$password" | chpasswd
echo "root:$password" | chpasswd

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install text editor
pacman -S --noconfirm $text_editor

EOF

# Unmount and reboot
umount -R /mnt
echo "Installation complete! Rebooting..."
reboot
