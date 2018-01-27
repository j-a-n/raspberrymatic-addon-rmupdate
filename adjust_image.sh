#!/bin/bash -e

LOOP_DEV=7
BOOT_SIZE=$((250*1024*1024))
ROOT_SIZE=$((1000*1024*1024))
USR_LOCAL_SIZE=$((4*1024*1024))

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root." 1>&2
	exit 1
fi

image_file="$(realpath $1)"
new_image_file="${image_file/\.img/\.rmupdate\.img}"

if [[ ! -e ${image_file} ]]; then
	echo "File not found: ${image_file}." 1>&2
	exit 1
fi

if [[ ! $image_file =~ .*\.img ]]; then
	echo "Not an image file: ${image_file}." 1>&2
	exit 1
fi

tinker=0
[[ $(basename $image_file) =~ .*tinkerboard.* ]] && tinker=1

part_start=512
[ $tinker == 1 ] && part_start=$((906*512))

echo "image: ${image_file}"
echo "adjusted image: ${new_image_file}"

echo "*** Creating new image file and partitions ***"
dd if=/dev/zero of=$new_image_file bs=512 count=$(( ((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}+${USR_LOCAL_SIZE})/512) ))

parted --script $new_image_file \
	mklabel msdos \
	mkpart primary fat32 ${part_start}B $((${part_start}+${BOOT_SIZE}-512))B \
	set 1 boot on \
	mkpart primary ext4 $((${part_start}+${BOOT_SIZE}))B $((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}-512))B \
	mkpart primary ext4 $((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}))B $((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}-512))B \
	mkpart primary ext4 $((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}+${ROOT_SIZE}))B 100%

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
	[ "$num" = "2" ] && seek=$(((${part_start}+${BOOT_SIZE})/512))
	[ "$num" = "3" ] && seek=$(((${part_start}+${BOOT_SIZE}+${ROOT_SIZE}+${ROOT_SIZE})/512))
	dd if=$image_file of=$new_image_file bs=512 skip=$start count=$size seek=$seek conv=notrunc
done

if [ $tinker == 1 ]; then
	echo "*** Copying boot loader ***"
	dd if=$image_file of=$new_image_file bs=512 skip=1 count=$((($part_start/512)-2)) seek=1 conv=notrunc
fi


echo "*** Creating / resizing filesystems ***"
umount /tmp/rmupdate.mnt 2>/dev/null || true
rmdir /tmp/rmupdate.mnt 2>/dev/null || true
rm /tmp/rmupdate.boot.tar 2>/dev/null || true
rm /dev/mapper/loop${LOOP_DEV}p 2>/dev/null || true
kpartx -d /dev/loop${LOOP_DEV} 2>/dev/null || true
losetup -d /dev/loop${LOOP_DEV} 2>/dev/null || true

losetup /dev/loop${LOOP_DEV} $image_file
kpartx -a /dev/loop${LOOP_DEV}
ln -s /dev/loop${LOOP_DEV} /dev/mapper/loop${LOOP_DEV}p

sleep 3

mkdir /tmp/rmupdate.mnt
mount /dev/mapper/loop${LOOP_DEV}p1 /tmp/rmupdate.mnt
(cd /tmp/rmupdate.mnt; tar cf /tmp/rmupdate.boot.tar .)
umount /tmp/rmupdate.mnt

rm /dev/mapper/loop${LOOP_DEV}p 2>/dev/null || true
kpartx -d /dev/loop${LOOP_DEV} 2>/dev/null || true
losetup -d /dev/loop${LOOP_DEV} 2>/dev/null || true

sleep 3

losetup /dev/loop${LOOP_DEV} $new_image_file
kpartx -a /dev/loop${LOOP_DEV}
ln -s /dev/loop${LOOP_DEV} /dev/mapper/loop${LOOP_DEV}p

sleep 3

partuuid=$(blkid -s PARTUUID -o value /dev/mapper/loop${LOOP_DEV}p2)
echo "PARTUUID=${partuuid}"

mkfs.vfat -F32 -n bootfs  /dev/mapper/loop${LOOP_DEV}p1
sleep 3
mount /dev/mapper/loop${LOOP_DEV}p1 /tmp/rmupdate.mnt
(cd /tmp/rmupdate.mnt; tar xf /tmp/rmupdate.boot.tar .)

bootconf=cmdline.txt
#[ $tinker == 1 ] && bootconf=extlinux/extlinux.conf
# /etc/init.d/S00eQ3SystemStart needs adaption before PARTUUID can be used
if [ $tinker == 0 ]; then
	sed -i -r s"/root=\S+/root=PARTUUID=${partuuid}/" /tmp/rmupdate.mnt/${bootconf}
fi
umount /tmp/rmupdate.mnt

rm /tmp/rmupdate.boot.tar
rmdir /tmp/rmupdate.mnt

#fsck.vfat -a /dev/mapper/loop${LOOP_DEV}p1
#fatresize --size $BOOT_SIZE /dev/mapper/loop${LOOP_DEV}p1

sleep 3

echo "resize /dev/mapper/loop${LOOP_DEV}p2"
fsck.ext4 -f -y /dev/mapper/loop${LOOP_DEV}p2 || true
resize2fs /dev/mapper/loop${LOOP_DEV}p2
tune2fs -L rootfs1 /dev/mapper/loop${LOOP_DEV}p2
sleep 3

echo "mkfs /dev/mapper/loop${LOOP_DEV}p3"
mkfs.ext4 -L rootfs2 /dev/mapper/loop${LOOP_DEV}p3 || true
sleep 3

echo "resize /dev/mapper/loop${LOOP_DEV}p4"
fsck.ext4 -f -y /dev/mapper/loop${LOOP_DEV}p4 || true
resize2fs /dev/mapper/loop${LOOP_DEV}p4



rm /dev/mapper/loop${LOOP_DEV}p
kpartx -d /dev/loop${LOOP_DEV}
losetup -d /dev/loop${LOOP_DEV}

echo "*** Adjusted image successfully created ***"

