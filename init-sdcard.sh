#! /bin/bash -e
MNT=/run/media/$USER
BOOT=$(echo -n $MNT/boot*)
echo BOOT=$BOOT

if [[ ! -d $BOOT ]]; then
    echo "Did not find $MNT/boot*, trying to mound sdcard"
    dev=$(lsblk -d -o NAME,MODEL,SIZE | grep -E '(uSD|USB DISK).*[0-9][0-9]\.[0-9]G' | cut -d" " -f1)
    if [[ -z $dev ]]; then echo "No device found"; exit 1; fi
    udisksctl mount -b /dev/${dev}1
    udisksctl mount -b /dev/${dev}2
    sleep 2
    ls $MNT
fi

if [[ ! -d $BOOT ]]; then
    echo "Cannot find SD card at $MNT/boot*"
    echo "Did you perhaps forget to remove and re-insert the SD card after flashing?"
    exit 1
fi

if [[ ! -d $MNT/rootfs/home/gnome ]]; then
    mkdir -p $MNT/rootfs
    sudo mount /dev/sdc2 $MNT/rootfs
fi

PI=$MNT/rootfs/home/gnome

cp ~/.tmux.* $PI || true
mkdir -p $PI/.ssh
chmod 700 $PI/.ssh
cp ~/.ssh/lberrigan-2022.pub $PI/.ssh/authorized_keys
sudo sed -i -e '/^%sudo/s/ALL$/NOPASSWD: ALL/' $MNT/rootfs/etc/sudoers

sync
