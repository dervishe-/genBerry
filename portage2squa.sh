#!/bin/bash
# vim: foldmarker={{{,}}}
#
# portage2squa.sh
# Author: Alexndre Keledjian <dervishe@yahoo.fr>
# Version: 1.0
# License: GPLv3
# 
#
# This script download the portage tree and make a squashfs file with it
#

#{{{ Parameters
LOCATION=http://distfiles.gentoo.org/snapshots
FILE=portage-latest.tar.xz
SIG=${FILE}.gpgsig
HASH=${FILE}.md5sum
WDIR=./repository_alt
TEST_DIR=./mnt
SQUASH_FILE=portage.squashfs
LOCAL_PORTAGE_DIR=portage
#}}}
. ./helpers.sh

echo -e "\t$HSTAR Checking requirements (1/11): " #{{{
echo -en "\t\t$HSTAR Is gpg installed ? "
checkGPG
echo -en "\t\t$HSTAR Are squashfs tools installed ? "
which mksquashfs >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -eq 1 ]] && exit 1
echo -en "\t\t$HSTAR Are you root ? "
checkRoot
echo -en "\t\t$HSTAR Are you connected ? "
checkConnectivity
#}}}

echo -en "\t$HSTAR Building working dir (2/11): " #{{{
([[ -d $WDIR ]] || mkdir "$WDIR") && cd "$WDIR" >> $LOG 2>&1
printResult $?
#}}}

echo -en "\t$HSTAR Retrieving the fingerprint (3/11): " #{{{
[[ -f $HASH ]] && rm $HASH
getFile $LOCATION/$HASH
#}}}

echo -en "\t$HSTAR Retrieving the portage archive (4/11): " #{{{
retrieveFile $FILE $HASH $LOCATION
#}}}

echo -en "\t$HSTAR Checking file's fingerprint (5/11): " #{{{
checkFingerprint $HASH
#}}}

echo -en "\t$HSTAR Retrieving the file's signature (6/11): " #{{{
getFile $LOCATION/$SIG
#}}}

echo -en "\t$HSTAR Checking file's signature (7/11): " #{{{
checkSignature $SIG $FILE
if [[ $? -ne 0 ]]; then
	echo -e "\t\tSignature's problem: the file don't seems to be legit..."
	echo -e "\t\tPerhap's you don't have imported the Gentoo public key:"
	echo -e "\t\thttps://www.gentoo.org/downloads/signatures/"
	exit 1;
fi
#}}}

echo -en "\t$HSTAR Expanding the portage tree (8/11): " #{{{
tar -xJpf $FILE >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
if [[ $BUFFER -ne 0 ]]; then
	echo -e "\t\tCheck the free space in your filesystem."
	echo -e "\t\tDon't forget to erase the '$LOCAL_PORTAGE_DIR' directory before"
	echo -e "\t\trunning this script again."
	exit 1;
fi
#}}}

echo -en "\t$HSTAR Building the Portage Squash image (9/11): " #{{{
mksquashfs $LOCAL_PORTAGE_DIR $SQUASH_FILE >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
[[ $BUFFER -ne 0 ]] && exit 1
#}}}

echo -en "\t$HSTAR Testing the new image (10/11): " #{{{
[[ -d $TEST_DIR ]] || mkdir $TEST_DIR >> $LOG 2>&1
mount -o loop -t squashfs $SQUASH_FILE $TEST_DIR >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
if [[ $BUFFER -ne 0 ]]; then
	echo -e "\t\tUnable to mount the new squash image."
	echo -e "\t\tCheck your kernel if it can handle them"
	echo -e "\t\tOr if you have the authorization to mount squashfs volumes."
	exit 1
fi
umount $TEST_DIR
#}}}

echo -en "\t$HSTAR Cleaning all the stuffs (11/11): " #{{{
cd .. >> $LOG 2>&1
mv $WDIR/$SQUASH_FILE . >> $LOG 2>&1
BUFFER=$?
if [[ $BUFFER -ne 0 ]]; then
	printResult $BUFFER
	echo -e "\t\tUnable to move the squashfs file: '$SQUASH_FILE' from the temporary directory"
	exit 1
fi
rm -Rf $WDIR >> $LOG 2>&1
BUFFER=$?
printResult $BUFFER
if [[ $BUFFER -ne 0 ]]; then
	echo -e "\t\tUnable to clean and delete the temporary directory"
	exit 1
fi
#}}}
exit 0