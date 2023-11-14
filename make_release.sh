#!/bin/bash


MOUNT_ROOT=./root
MOUNT_BOOT=./boot


# Helper functions
# Error out if the given command is not found on the PATH.
function check_dependency {
    dependency=$1
    command -v $dependency >/dev/null 2>&1 || {
        echo >&2 "${dependency} not found. Please make sure it is installed and on your PATH."; exit 1;
    }
}

# Add sbin to the PATH to check for commands available to sudo
function check_sudo_dependency {
    dependency=$1
    local PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
    check_dependency $dependency
}

# Determine if wget supports the --show-progress option (introduced in
# 1.16). If so, make use of that instead of spewing out redirects and
# loads of info into the terminal.
function wget_cmd {
    wget --show-progress > /dev/null 2>&1
    status=$?

    # Exit code 2 means command parsing error (i.e. option does not
    # exist).
    if [ "$status" == "2" ]; then
        echo "wget -O"
    else
        echo "wget -q --show-progress -O"
    fi
}

# Check dependencies
check_dependency "sudo"
check_dependency "wget"
check_dependency "tar"
check_dependency "unzip"
check_dependency "lsblk"
check_dependency "jq"
check_sudo_dependency "parted"
check_sudo_dependency "mkfs.ext4"
check_sudo_dependency "losetup"
check_sudo_dependency "sfdisk"


#create loop file for raw.img
sudo dd if=/dev/zero of=emmc.img bs=1 count=0 seek=3G
DEVICE_NODE="./emmc.img"

#Delete all partitions
sudo sfdisk --delete $DEVICE_NODE

#Create partitions
sudo parted $DEVICE_NODE mklabel msdos --script
sudo parted $DEVICE_NODE mkpart primary ext4 32MB 256MB --script
sudo parted $DEVICE_NODE mkpart primary ext4 256MB 2048MB --script

if [ $DEVICE_NODE == "./emmc.img" ]; then
	echo "Prepare loop file"
	sudo losetup -D
	sudo losetup -Pf emmc.img
	LOOP_NODE=`ls /dev/loop?p1 | cut -c10-10`
	DEVICE_NODE="/dev/loop$LOOP_NODE"
fi

# use p1, p2 extentions instead of 1, 2 when using sd drives
BOOTPART="${DEVICE_NODE}p1"
ROOTPART="${DEVICE_NODE}p2"

sudo mkfs.ext4 -F -L boot $BOOTPART -O ^metadata_csum,^orphan_file # 1st partition = boot
sudo mkfs.ext4 -F -L root $ROOTPART -O ^metadata_csum,^orphan_file # 2nd partition = root

# Flashing rootFS
echo -e "\e[1mFlashing rootFS...\e[0m"
mkdir "$MOUNT_ROOT"
TEMP=`ls *.tar.bz2`
echo "$TEMP"

sudo mount $ROOTPART "$MOUNT_ROOT" # Mount root partition
sudo tar -xpf "$TEMP" -C "$MOUNT_ROOT"
sync

# Copying kernel to boot partition
echo -e "\e[1mCopying kernel to boot partition...\e[0m"
mkdir "$MOUNT_BOOT"
sudo mount $BOOTPART "$MOUNT_BOOT" # Mount boot partition
echo "Boot partition mount: $MOUNT_BOOT"
sudo sh -c "cp -r $MOUNT_ROOT/boot/* $MOUNT_BOOT"

echo -e "\e[1mCopying overlay files...\e[0m"
sudo sh -c "cp -r ./overlay/* $MOUNT_ROOT/"

#Copy boot script
echo `ls $MOUNT_BOOT`
echo -e "\e[1mCopying UBoot script to boot partition...\e[0m"
sudo sh -c "cp '$MOUNT_BOOT/boot.pinephonepro.scr' '$MOUNT_BOOT/boot.scr'"
sync

#Install the bootloader
echo -e "\e[1mInstalling u-boot bootloader...\e[0m"
sudo dd if=u-boot-rockchip.bin of=$DEVICE_NODE oflag=direct seek=64
sync

# Clean up files
echo -e "\e[1mCleaning up!\e[0m"
for PARTITION in $(ls ${DEVICE_NODE}*)
do
    echo "Unmounting $PARTITION"
    sudo umount $PARTITION
done

sudo losetup -D
sudo rm -rf "$MOUNT_ROOT"
sudo rm -rf "$MOUNT_BOOT"

# Done :)
echo -e "\e[1mFlashing $DEVICE_NODE OK!\e[0m"
