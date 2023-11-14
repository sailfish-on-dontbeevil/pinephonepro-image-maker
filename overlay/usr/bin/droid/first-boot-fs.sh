#!/bin/sh
DEVICE_NODE=/dev/mmcblk2

echo "First boot filesystem setup...." > /dev/tty0

#Resize the root fs if the home partition doesnt exist
if [ -e ${DEVICE_NODE}p3 ]; then
        echo "Home partition exists, unable to resize root" > /dev/tty0
else
        #Check current battery capacity
        CAP=`cat /sys/class/power_supply/rk818-battery/capacity`
        echo "Current battery capacity is $CAP" > /dev/tty0

        if [ "$CAP" -lt "15" ]; then
                echo "Please charge to 15% before performing the first boot" > /dev/tty0
                echo "Device will shutdown in 10 seconds..." > /dev/tty0
                sleep 10
                halt -f
                exit 1
        fi

        echo "Resizing root...." > /dev/tty0

        parted $DEVICE_NODE resizepart 2 8192 --script
        resize2fs ${DEVICE_NODE}p2

        echo "Creating home partition..." > /dev/tty0

        #Create a 3rd partition for home.  Community encryption will format it.
        parted $DEVICE_NODE mkpart primary ext4 8192MB 100% --script
        mkfs.ext4 -F -L home ${DEVICE_NODE}p3
fi
echo "Done" > /dev/tty0
