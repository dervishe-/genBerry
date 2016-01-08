#!/bin/bash
# vim: foldmarker={{{,}}}
#
# imagebuilder.sh
# Author: Alexndre Keledjian <dervishe@yahoo.fr>
# Version: 1.0
# License: GPLv3
# 
#
# This script build an sdcard image
#	Parameters list:
#		rPi type 1(A, A+, B, B+, zero) or 2
#

#{{{ Parameters
LOCATION=https://debrouillonet.org/
FILE=genBerry.tar.xz
SIG=${FILE}.gpgsig
HASH=${FILE}.md5sum
DEVICE=/dev/mmcblk0
MOUNT_POINT=./mnt
WDIR=./repository
RASP_TYPE="$1"
echo $RASP_TYPE
# Check for a correct raspberry type
if ! [[ $RASP_TYPE -eq 1 ]] && ! [[ $RASP_TYPE -eq 2 ]]; then
	echo "Bad RaspBerry type (1|2): $RASP_TYPE"
	exit 1
fi
# Here we assume that each sector's size is 512 bytes
DISK_SIZE=$(($(sfdisk -s $DEVICE) * 2))
LAYOUT="2048,65536,c\n67584,,83"
[[ $DISK_SIZE -lt 8388608 ]] && TAG_EXT4="-T small" || TAG_EXT4=""
#}}}
. ./helpers.sh

clear
echo -e "$HSTAR Checking requirements (1/13): " #{{{
echo -en "\t$HSTAR Is ${DEVICE} exists ? "
ls $DEVICE >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -ne 0 ]] && exit 1
echo -en "\t$HSTAR Is gpg installed ? "
checkGPG
echo -en "\t$HSTAR Is partprobe installed ? "
which partprobe >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 1 ]] && exit 1
echo -en "\t$HSTAR Are you root ? "
checkRoot
echo -en "\t$HSTAR Are you connected ? "
checkConnectivity
#}}}
echo -ne "\n\e[1;31mAll the things seems ok, would you like to install the image on \e[0m\e[5m${DEVICE}\e[0m\e[1;31m (yes|[No]) ?\e[0m "
read rep
[[ $rep =~ [Yy](es)? ]] || exit 1
echo -e "\nThe log file will be stored here: ${LOG}\n"

echo -en "$HSTAR Building working dir (2/13): " #{{{
([[ -d $WDIR ]] || mkdir "$WDIR") && cd "$WDIR" >> $LOG 2>&1
printResult $?
#}}}

echo -en "$HSTAR Retrieving the fingerprint (3/13): " #{{{
[[ -f $HASH ]] && rm $HASH
getFile $LOCATION/$HASH
#}}}

echo -en "$HSTAR Retrieving stage 4 (4/13): " #{{{
retrieveFile $FILE $HASH $LOCATION
#}}}

echo -en "$HSTAR Checking the new file's fingerprint (5/13): " #{{{
checkFingerprint $HASH
#}}}

echo -en "$HSTAR Retrieving the file's signature (6/13): " #{{{
getFile $LOCATION/$SIG
#}}}

echo -en "$HSTAR Checking file's signature (7/13): " #{{{
checkSignature $SIG $FILE
if [[ $? -ne 0 ]]; then
	echo -e "\tSignature's problem: the file don't seems to be legit..."
	echo -e "\tPerhap's you don't have imported my public key:"
	echo -e "\thttps://keybase.io/dervishe/key.asc"
	exit 1;
fi
#}}}

echo -en "$HSTAR Partitionning the sdcard (8/13): " #{{{
echo -e $LAYOUT | sfdisk $DEVICE >> $LOG 2>&1
partprobe $DEVICE >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 0 ]] || exit 1
#}}}

echo -e "$HSTAR Formating the sdcard (9/13): " #{{{
BOOT=$(sfdisk -l $DEVICE | grep "^/dev" | cut -d ' ' -f 1 | grep 1)
ROOT=$(sfdisk -l $DEVICE | grep "^/dev" | cut -d ' ' -f 1 | grep 2)
echo -en "\t$HSTAR $BOOT in FAT16: "

mkfs.vfat -F 16 $BOOT >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 0 ]] || exit 1
echo -en "\t$HSTAR $ROOT in ext4: "
mkfs.ext4 $TAG_EXT4 $ROOT >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 0 ]] || exit 1
#}}}

echo -e "$HSTAR Mounting partitions (10/13): " #{{{
echo -en "\t$HSTAR root: "
[[ -d $MOUNT_POINT ]] || mkdir $MOUNT_POINT >> $LOG 2>&1
mount $ROOT $MOUNT_POINT
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 0 ]] || exit 1
echo -en "\t$HSTAR boot: "
mkdir ${MOUNT_POINT}/boot >> $LOG 2>&1
if [[ $? -ne 0 ]]; then
	umount $MOUNT_POINT >> $LOG 2>&1
	printResult 1
	exit 1
fi
mount $BOOT ${MOUNT_POINT}/boot
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 0 ]] || exit 1
#}}}

echo -en "$HSTAR Expanding the image on sdcard (11/13): " #{{{
tar -xJpf $FILE -C $MOUNT_POINT >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
if [[ $BUFFER -ne 0 ]]; then
	echo -e "\tCheck the free space in your sdcard."
	echo -e "\tWait until all the filesystems are unmounted..."
	sync
	umount ${MOUNT_POINT}/{boot,} >> $LOG 2>&1
	exit 1;
fi
#}}}

echo -e "$HSTAR Installing new kernel (12/13): " #{{{
cd .. >> $LOG 2>&1
./kernelbuilder.sh ../../${WDIR}/$MOUNT_POINT $RASP_TYPE $LOCATION
cd - >> $LOG 2>&1
#}}}

echo -e "$HSTAR Creating portage tree on squashfs (13/13): " #{{{
cd .. > /dev/null 2>&1
${WDIR}/${MOUNT_POINT}/root/portage/portage2squa.sh
mv ./portage.squashfs ${WDIR}/${MOUNT_POINT}/root/portage/ > /dev/null 2>&1
cd - > /dev/null 2>&1
#}}}

echo -e "$HSTAR Cleaning all the stuffs (14/13): " #{{{
echo -en "\t$HSTAR Syncing sdcard: "
sync && printResult 0
echo -en "\t$HSTAR Unmounting directory: "
umount ${MOUNT_POINT}/{boot,} >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -ne 0 ]] && exit 1
cd .. >> $LOG 2>&1
echo -en "\t$HSTAR Deleting stuffs: "
rm -Rf $WDIR >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
if [[ $BUFFER -ne 0 ]]; then
	echo -e "\tUnable to clean and delete the temporary directory"
	exit 1
fi
#}}}
exit 0