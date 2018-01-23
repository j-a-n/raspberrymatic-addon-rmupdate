#!/bin/bash -e

LOOP_DEV=7
BOOT_SIZE=$((100*1024*1024))
GAP_SIZE=$((200*1024*1024)) # Reserved space for future use
ROOT_SIZE=$((1000*1024*1024))
USR_LOCAL_SIZE=$((2*1024*1024))


if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." 1>&2
	exit 1
fi

image_file="$(realpath $1)"
new_image_file="${image_file/\.img/\.rmupdate\.img}"

if [[ ! $image_file =~ .*\.img ]]; then
	echo "Not an image file: ${image_file}." 1>&2
	exit 1
fi

echo "image: ${image_file}"
echo "adjusted image: ${new_image_file}"

echo "*** Creating new image file and partitions ***"
dd if=/dev/zero of=$new_image_file bs=1M count=$((((${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}+${USR_LOCAL_SIZE})/1024/1024)+1))
parted --script $new_image_file \
	mklabel msdos \
	mkpart primary fat32 512B ${BOOT_SIZE}B \
	set 1 boot on \
	mkpart primary ext4 $((512+${BOOT_SIZE}+${GAP_SIZE}))B $((${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}))B \
	mkpart primary ext4 $((512+${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}))B $((${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}))B \
	mkpart primary ext4 $((512+${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}))B 100%

echo "*** Copying original partitons ***"
oIFS="$IFS"
IFS=$'\n'
for line in $(parted $image_file unit B print | grep primary); do
	IFS=$oIFS
	x=($line)
	num=${x[0]}
	start=$((${x[1]:0: -1}/512))
	size=$((${x[3]:0: -1}/512))
	echo $num - $start - $size
	seek=0
	[ "$num" = "1" ] && seek=$start
	[ "$num" = "2" ] && seek=$(((512+${BOOT_SIZE}+${GAP_SIZE})/512))
	[ "$num" = "3" ] && seek=$(((512+${BOOT_SIZE}+${GAP_SIZE}+${ROOT_SIZE}+${ROOT_SIZE})/512))
	dd if=$image_file of=$new_image_file bs=512 skip=$start count=$size seek=$seek conv=notrunc
done

echo "*** Resizing / creating filesystems ***"
rm /dev/mapper/loop${LOOP_DEV}p 2>/dev/null || true
kpartx -d /dev/loop${LOOP_DEV} 2>/dev/null || true
losetup -d /dev/loop${LOOP_DEV} 2>/dev/null || true

losetup /dev/loop${LOOP_DEV} $new_image_file
kpartx -a /dev/loop${LOOP_DEV}
ln -s /dev/loop${LOOP_DEV} /dev/mapper/loop${LOOP_DEV}p

#fsck.vfat -a /dev/mapper/loop${LOOP_DEV}p1
fatresize --size $BOOT_SIZE /dev/mapper/loop${LOOP_DEV}p1
fsck.ext4 -f -y /dev/mapper/loop${LOOP_DEV}p2
resize2fs /dev/mapper/loop${LOOP_DEV}p2
tune2fs -L rootfs1 /dev/mapper/loop${LOOP_DEV}p2
mkfs.ext4 -L rootfs2 /dev/mapper/loop${LOOP_DEV}p3
fsck.ext4 -f -y /dev/mapper/loop${LOOP_DEV}p4
resize2fs /dev/mapper/loop${LOOP_DEV}p4

partuuid=$(blkid -s PARTUUID -o value /dev/mapper/loop${LOOP_DEV}p2)
mkdir /tmp/rmupdate.mnt
mount /dev/mapper/loop${LOOP_DEV}p1 /tmp/rmupdate.mnt
sed -i -r s"/root=\S+/root=PARTUUID=${partuuid}/" /tmp/rmupdate.mnt/cmdline.txt
umount /tmp/rmupdate.mnt
rmdir /tmp/rmupdate.mnt

rm /dev/mapper/loop${LOOP_DEV}p
kpartx -d /dev/loop${LOOP_DEV}
losetup -d /dev/loop${LOOP_DEV}

echo "*** Adjusted image successfully created ***"

