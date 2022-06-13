# Encrypted Archzfs install script - no guardrails on this! Use at your own risk!
# This is mostly copied from the Arch Wiki 'Install Arch Linux on ZFS'
# https://wiki.archlinux.org/index.php/Install_Arch_Linux_on_ZFS

# set up archzfs repo for livecd
curl https://eoli3n.github.io/archzfs/init | bash

# partition for uefi and zfsroot on /dev/sda
## CHANGE /dev/sda to appropriate disk
## this will delete the partition table, add one 512MB efi partition,
## and the rest of the disk for zfs
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart esp 0% 512
parted -s /dev/sda mkpart archzfs 512 100%
parted -s /dev/sda set 1 esp on

# zfs setup
modprobe zfs

## CHECK disk blocksize with #blkid -o NAME,PHY-SEC 
## if blocksize=512, set ashift=9, otherwise leave as set
## This will prompt for a zfs encryption password
zpool create -f -o ashift=12 \
-O acltype=posixacl       \
-O relatime=on            \
-O xattr=sa               \
-O dnodesize=legacy       \
-O normalization=formD    \
-O mountpoint=none        \
-O canmount=off           \
-O devices=off            \
-R /mnt                   \
-O compression=lz4        \
-O encryption=aes-256-gcm \
-O keyformat=passphrase   \
-O keylocation=prompt     \
zroot /dev/disk/by-partlabel/archzfs 

## datasets created to prepare for boot environments
zfs create -o mountpoint=none zroot/data
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
zfs create -o mountpoint=/home zroot/data/home
zfs create -o mountpoint=/root zroot/data/home/root
zfs create -o mountpoint=/var -o canmount=off     zroot/var
zfs create                                        zroot/var/log
zfs create -o mountpoint=/var/lib -o canmount=off zroot/var/lib
zfs create                                        zroot/var/lib/libvirt
zfs create                                        zroot/var/lib/docker

# export and remount zpool, will prompt for the password again
zpool export zroot
zpool import -d /dev/disk/by-partlabel -R /mnt zroot -N
zfs load-key zroot
zfs mount zroot/ROOT/default
zfs mount -a

zpool set bootfs=zroot/ROOT/default zroot
zpool set cachefile=/etc/zfs/zpool.cache zroot

# installation of archlinux
## Add any additional software you want installed after dhcpcd 
mkdir /mnt/boot
mkfs.vfat -F 32 /dev/sda1
mount /dev/sda1 /mnt/boot
pacstrap /mnt base base-devel linux linux-firmware iwd vim git dhcpcd

echo "/dev/sda1 /boot vfat defaults 0 0" >> /mnt/etc/fstab
mkdir /mnt/etc/zfs && cp /etc/zfs/zpool.cache /mnt/etc/zfs

## CHANGE America/Chicago to your local timezone and en_US.UTF-8 to your C locale
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

## CHANGE to preferred hostname
echo "archzfs-lap" > /mnt/etc/hostname
echo "127.0.0.1		localhost \n::1			localhost \n127.0.1.1 	archzfs-lap.localdomain archzfs-lap" >> /etc/hosts

# set up archzfs repo in installation
cat >> /mnt/etc/pacman.conf <<"EOF"
[archzfs]
Server = https://archzfs.com/archzfs/x86_64
Server = http://mirror.sum7.eu/archlinux/archzfs/archzfs/x86_64
Server = https://mirror.biocrafting.net/archlinux/archzfs/archzfs/x86_64
EOF

arch-chroot /mnt pacman-key -r DDF7DB817396A49B2A2723F7403BD972F75D9D76
arch-chroot /mnt pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76
arch-chroot /mnt pacman -S --noconfirm zfs-linux

# install systemd-boot
arch-chroot /mnt bootctl install
cat >> /mnt/boot/loader/loader.conf <<"EOF"
default    archlinux
timeout    5
editor     no 
EOF
cat >> /mnt/boot/loader/entries/archlinux.conf <<"EOF"
title           Arch Linux
linux           vmlinuz-linux
initrd          initramfs-linux.img
options         zfs=zroot/ROOT/default rw
EOF

# mkinicpio tweaks to add zfs support to initram
sed -i 's/^HOOKS.*/HOOKS="base udev autodetect modconf block keyboard zfs filesystems"/' /mnt/etc/mkinitcpio.conf

# install systemd zfs and network targets and hostid
systemctl enable zfs.target --root=/mnt
systemctl enable zfs-import-cache --root=/mnt
systemctl enable zfs-mount --root=/mnt
systemctl enable zfs-import.target --root=/mnt
systemctl enable iwd --root=/mnt
systemctl enable dhcpcd.service --root=/mnt
arch-chroot /mnt zgenhostid $(hostid)
arch-chroot /mnt mkinitcpio -p linux

# will prompt to create root password
arch-chroot /mnt passwd

# unmount and export pool
umount /mnt/boot
zfs umount -a
zpool export zroot
