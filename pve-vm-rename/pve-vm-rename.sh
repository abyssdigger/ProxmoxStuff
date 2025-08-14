#!/bin/bash

# Source: https://github.com/abyssdigger/ProxmoxStuff/tree/main/pve-vm-rename/pve-vm-rename.sh
# Copyright 2025 abyssdigger
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0


ECP="--exec"	# Option to exec commands if all VM disk storage types are supported
ECY="--force"	# Option to exec commands even if some VM disk storage types are unknown

# Help
if [ $# -gt 0 ] && ( [ $1 == "-h" ] || [ $1 == "--help" ] ); then
	echo "Usage: "$(basename "$0")" <old-vmid> <new-vmid> [$ECP|$ECY]"
	echo "Change Proxmox virtual machine's VMID from <old-vmid> to <new-vmid>"
	echo "<old-vmid> (integer 1 - N): The ID of an existing stopped VM."
	echo "<new-vmid> (integer 1 - N): New ID to change to. Must not be used by existing cluster VMs."
	echo "Extra options:"
 	echo "  $ECP: prepare and execute commands to rename VMID."
	echo "  $ECY: prepare and execute commands even if unsupported storage found (DANGEROUS!)."
	echo "Without extra options just prepares and lists commands to rename VM (ready to copy-paste)."
	echo
	echo "Help (this one): "$(basename "$0")" -h"
	echo
	echo "******************************************************************************************"
	echo "*ATTENTION! Only RBD(ceph), Dir, LVM Thin and LVM (untested) storage types are supported!*"
	echo "*      Virtual disks on storages of other types like ZFS, NFS, SMB/CIFS, iSCSI etc       *"
	echo "*         may become inaccessible and should be moved to the new VMID manually.          *"
	echo "******************************************************************************************"
	exit 0
fi

# Check params
if [ "$#" -ge 2 ] && [ "$#" -le 3 ] && [[ "$1" =~ ^[0-9]+$ ]] && [[ "$2" =~ ^[0-9]+$ ]] && ([ "$#" -eq 2 ] || [[ "$3" =~ ^("$ECP"|"$ECY") ]])
then
	VMID_OLD="$1"
	VMID_NEW="$2"
	EXECUTOR="$3"
else
	echo "Usage: "$(basename "$0")" <old-vmid> <new-vmid> [OPTIONS]"
	echo "Try '"$(basename "$0")" --help' for more information."
        exit 64
fi

# Check if runs under root/sudo
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root (try to run with sudo)"
	exit 126
fi

echo -n "Job started: rename VM $VMID_OLD to $VMID_NEW, mode: "
if [ "${#EXECUTOR}" -eq 0 ]; then
	echo "dry run (list commands to rename VM)."
else
	echo "execute (run commands to rename VM)."
fi
echo "---------------------------------------------------------------------------------------"
echo "Check VM and VMID preconditions:"

# Check VM state and new VMID availability
N=0

((N++))
echo -n "[$N] check VM existence: <qm status $VMID_OLD>: "
VM_STATUS=$(qm status "$VMID_OLD" 2>&1);
RES="$?"
if [ "$RES" -ne 0 ]; then
	echo "ERROR($RES), output: "
	echo "$VM_STATUS"
	exit "$(expr 100 + $N)"
else
	echo "OK."
fi

((N++))
echo -n "[$N] check new VMID is available ($VMID_NEW is not in /etc/pve/.vmlist): "
CMD='grep -E "\"'"$VMID_NEW"'\":" /etc/pve/.vmlist 2>&1 | grep -oE "^.+\{.+[^\}]\}" 2>&1'
VMID_CHECK=$(eval $CMD);
RES="$?"
if [ "$RES" -eq 0 ]; then
	echo "ERROR, found VM with VMID=$VMID_NEW: "
	echo "$VMID_CHECK"
	exit "$(expr 100 + $N)"
else
	echo "OK."
fi

((N++))
if [ "${#EXECUTOR}" -ne 0 ]; then
	echo -n "[$N] check VM status (must be stopped): "
	if [ "$VM_STATUS" != "status: stopped" ]; then
		echo "ERROR, VM $VMID_OLD $VM_STATUS"
		exit "$(expr 100 + $N)"
	else
		echo "OK."
	fi
fi

DIRS_TO_RENAME=()
FILES_TO_RENAME=()
FILES_TO_UPDATE=()
COMMAND_LIST=()
declare -A COMMAND_DESC

DEVTYPES="scsi|efidisk|ide|sata|virtio"

# Add all files have to be renamed (@ - field separator, * - place to change old VMID)
FILES_TO_RENAME+=( "Rename firewall config file""@""/etc/pve/firewall/*.fw" )
FILES_TO_RENAME+=( "Rename VM config file""@""/etc/pve/qemu-server/*.conf" )

# Add commands to replace old VMID to new in config files (@ - field separator):
FILES_TO_UPDATE+=( "VM config - update disk names""@""/etc/pve/qemu-server/$VMID_OLD.conf""@""/^\(${DEVTYPES//|/\\|}\)[0-9]\+: .*:/s/\(base\|vm\)-$VMID_OLD\(-disk-\)/\1-$VMID_NEW\2/g")
FILES_TO_UPDATE+=( "VM config - update storage dirs""@""/etc/pve/qemu-server/$VMID_OLD.conf""@""s/\(^\(${DEVTYPES//|/\\|}\)[0-9]\+: .\+:\)$VMID_OLD\//\1$VMID_NEW\//g" )
FILES_TO_UPDATE+=( "Backup jobs - update VM names""@""/etc/pve/jobs.cfg""@""/^[[:space:]]\(vmid \|exclude \)/s/\([ ,]\)$VMID_OLD\(,\|$\)/\1$VMID_NEW\2/g" )
FILES_TO_UPDATE+=( "(untested) Replication - update VM names""@""/etc/pve/replication.cfg""@""/^.\+: $VMID_OLD-[0-9]\+$/s/\(: \)$VMID_OLD\(-[0-9]\+$\)/\1$VMID_NEW\2/p" )
FILES_TO_UPDATE+=( "Pool members - update VM names""@""/etc/pve/user.cfg""@""/^pool:.*/s/\([:,]\)$VMID_OLD\([:,]\)/\1$VMID_NEW\2/g")
FILES_TO_UPDATE+=( "HA config - update VM name""@""/etc/pve/ha/resources.cfg""@""s/\(^vm: \)$VMID_OLD/\1$VMID_NEW/g")

echo "---------------------------------------------------------------------------------------"
echo "Parse /etc/pve/qemu-server/$VMID_OLD.conf for virtual disks:"

RES_TOTAL=0

# Get all scsi drives for further rename (rbd/dir/lvm/lvmthin only! Other storage types are not implemented!)
while read -r line ; do
	#echo "> $line"
	NAME=$( echo "$line" | awk -F': ' '{print $1}')
	mapfile -t DATA < <( echo "$line" | awk -F': ' '{print $2}' | awk -F: '{print $1}{print $2}')
	echo -n "> $NAME ${DATA[0]}:${DATA[1]}: "
	STOR_DATA=$(pvesh get /storage/"${DATA[0]}" --output-format yaml)
	STOR_TYPE=$(echo "$STOR_DATA" | grep -E "^type: ")
	STOR_TYPE="${STOR_TYPE#type: }"
	if [ "$STOR_TYPE" == "rbd" ]; then
		LOOKUP="pool: "
		PLACE=$(echo "$STOR_DATA" | grep -E "^$LOOKUP")
		PLACE="${PLACE#$LOOKUP}"
		DIVIDER=" "
		NEWNAME="${DATA[1]/$VMID_OLD/$VMID_NEW}"
		COMMAND="rbd mv -p"
	elif [ "$STOR_TYPE" == "lvmthin" ] || [ "$STOR_TYPE" == "lvm" ]; then ### LVM IS UNTESTED!!!
		LOOKUP="vgname: "
		PLACE=$(echo "$STOR_DATA" | grep -E "^$LOOKUP")
		PLACE="${PLACE#$LOOKUP}"
		DIVIDER=" "
		NEWNAME="${DATA[1]/$VMID_OLD/$VMID_NEW}"
		COMMAND="lvrename"
	elif [ "$STOR_TYPE" == "dir" ]; then
		LOOKUP="path: "
		PLACE=$(echo "$STOR_DATA" | grep -E "^$LOOKUP")
		PLACE="${PLACE#$LOOKUP}/images"
		DIVIDER="/"
		if [[ ! " ${DIRS_TO_RENAME[*]} " =~ [[:space:]]"$PLACE"[[:space:]] ]]; then
  			DIRS_TO_RENAME+=( "$PLACE" )
		fi
		OLDFILE="${DATA[1]#$VMID_OLD}"
		NEWNAME="$PLACE$DIVIDER$VMID_OLD${OLDFILE/$VMID_OLD/$VMID_NEW}"
		#FILENAME="${DATA[1]#$VMID_OLD}"
		#NEWNAME="$PLACE$DIVIDER$VMID_OLD${FILENAME/$VMID_OLD/$VMID_NEW}"
		COMMAND="mv -f"
	else
		PLACE="UNKNOWN STORAGE TYPE $STOR_TYPE"
		DIVIDER=" FOR "
		NEWNAME=""
		COMMAND="echo '*** CHANGE DISK STORAGE MANUALLY ***'; exit 1 #"
		if [ "$EXECUTOR" == "$ECP" ]; then
			EXECUTOR=""
			RES_TOTAL=100
		fi
	fi
	COMMAND_TO_EXEC="$COMMAND $PLACE$DIVIDER${DATA[1]} $NEWNAME"
	COMMAND_LIST+=(  "$COMMAND_TO_EXEC"  )
	COMMAND_DESC+=( ["$COMMAND_TO_EXEC"]="Rename virtual disk $NAME [$STOR_TYPE:${DATA[0]}]" )

	echo "[$STOR_TYPE:$PLACE]."
done < <(grep -oE "^($DEVTYPES)[0-9]+: .*:($VMID_OLD\/)?(vm|base)-$VMID_OLD-disk-[0-9]+(\.(qcow2|raw|vmdk))?" /etc/pve/qemu-server/"$VMID_OLD".conf  | sort | uniq )

echo "---------------------------------------------------------------------------------------"
echo "Prepare command list to execute:"
echo -n "> commands to update VMID in config files... "
for each in "${FILES_TO_UPDATE[@]}"; do
	IFS="@" read  -r -a DATA <<< "${each}"
	if [ -f "${DATA[1]}" ]; then
		COMMAND="sed -i '${DATA[2]}' ${DATA[1]}"
		COMMAND_LIST+=(  "$COMMAND" )
		COMMAND_DESC+=( ["$COMMAND"]="${DATA[0]} in ${DATA[1]}" )
	fi
done
echo "OK."

echo -n "> commands to rename VM files... "
for each in "${FILES_TO_RENAME[@]}"; do
	IFS="@" read  -r -a DATA <<< "${each}"
	FILE_OLD="${DATA[1]/\*/$VMID_OLD}"
	FILE_NEW="${DATA[1]/\*/$VMID_NEW}"
	if [ -f "$FILE_OLD" ]; then
		COMMAND="mv -f $FILE_OLD $FILE_NEW"
		COMMAND_LIST+=(  "$COMMAND" )
		COMMAND_DESC+=( ["$COMMAND"]="${DATA[0]} $FILE_OLD" )
	fi
done
echo "OK."

echo -n "> commands to rename dirs named on VM... "
for each in "${!DIRS_TO_RENAME[@]}"; do
	COMMAND="mv -f ${DIRS_TO_RENAME[$each]}/$VMID_OLD ${DIRS_TO_RENAME[$each]}/$VMID_NEW"
	COMMAND_LIST+=(  "$COMMAND" )
	COMMAND_DESC+=( ["$COMMAND"]="Rename dir ${DIRS_TO_RENAME[$each]}/$VMID_OLD" )
done
echo "OK."

echo "---------------------------------------------------------------------------------------"
if [ "$EXECUTOR" != "$3" ]; then
	echo "*** Command execution cancelled, switched to dry run ***"
fi

if [ "${#EXECUTOR}" -ne 0 ] ; then
	echo "Executing commands to rename VM (exit code will show number of errors on execution):"
else
	echo "List commands to rename VM:"
	echo "#### CHECK VM IS STOPPED BEFORE EXECUTION!"
fi

for each in "${COMMAND_LIST[@]}"; do
	if [ "${#EXECUTOR}" -ne 0 ] ; then
		echo -n "> ${COMMAND_DESC[$each]}: "
		RES_TEXT=$(eval "$each" 2>&1)
		#RES_TEXT=$(echo "$each" 2>&1)
		RES="$?"
		if [ "$RES" -ne 0 ]; then
			echo "ERROR($RES), output:"
			echo "$RES_TEXT"
		else
			echo "OK."
		fi
	else
		echo "#### ${COMMAND_DESC[$each]}"
		echo "$each"
		RES=0
	fi
	(( RES_TOTAL += RES ))
done

echo "---------------------------------------------------------------------------------------"
echo -n "Job done "
if [ "${#EXECUTOR}" -eq 0 ] ; then
	echo -n "without any changes "
	if [ "$EXECUTOR" != "$3" ]; then
		echo "(execution cancelled due to errors, check logs above)."
	else
		echo "(run listed commands manually or use $ECP to execute them)."
	fi
elif [ "$RES_TOTAL" -ne 0 ]; then
	echo "with errors, check logs above! (it's a good idea to dry-run without $ECP first)"
else
	echo "with all commands executed successfully."
fi
exit "$RES_TOTAL"
