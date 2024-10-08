#!/bin/bash
# Importing and attaching a virtual disk image to an existing Proxmox VM:
# qm importdisk + qm set (search for the first free scsiX, set ssd/discsrd/iothread) + qm set (make bootable if --noboot not set)
# Usage: sudo ./pve-add-disk.sh <vmid> <disk> <storage> [--noboot]
# abyssdigger (c) 2024

if [[ "$#" -lt 3 ]]; then
   echo "Importing and attaching a virtual disk image to the Proxmox VM."
   echo
   echo "Usage: `basename $0` <vmid> <disk> <storage> [--noboot]"
   echo "<vmid>: The (unique) ID of the VM."
   echo "<disk>: Path to the disk image to import and attach (format has to be supported by qemu-img);"
   echo "<storage>: Target storage ID (use 'sudo pvesm status' to get list of available storages)."
   echo "--noboot: if _not_ set then <disk> will be attached to <vmid> as the only bootable device."
   exit 2
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (try to run with sudo)"
   exit 126
fi

VMID=$1
DISK=$2
STOR=$3
if [[ "$4" != "--noboot" ]]; then BOOT="TRUE"; fi

echo "vmid    : $VMID"
echo "file    : $DISK"
echo "storage : $STOR"
if [[ $BOOT == "TRUE" ]]; then
   echo "Disk will be set as the only bootable device (--noboot is not set)"
else
   echo "VM boot order will not be changed (--noboot is set)"
fi
echo '------------------------------'

echo "Checking VM $VMID configuration:"
CMD="qm config $VMID"
echo "[$CMD]"
RES=$(exec $CMD 2>&1)
ERR=$?
if [[ $ERR -ne 0 ]]; then
   echo "$RES"
   echo
   echo "Error getting VM configuration ($ERR), exiting."
   exit $ERR
fi
N=0
while [[ "$RES" == *"scsi${N}:"* ]]; do
   let N++
done
SCSI="scsi${N}"
echo "Disk will be attached to VM $VMID as HardDisk ($SCSI)."
echo '------------------------------'

echo "Importing disk image to pve:"
CMD="qm importdisk $VMID $DISK $STOR --format qcow2"
echo "[$CMD]"
exec 5>&1
set -o pipefail
RES=$(exec $CMD 2>&1 | tee >(cat - >&5))
ERR=$?
PRE=${RES%%"Successfully imported disk as '"*}
POS=${#PRE}
STR=${RES:${POS}}
if [[ ${#STR} -eq 0 ]]; then
   echo
   if [[ $ERR -ne 0 ]]; then
      echo "Error on importing disk image ($ERR), exiting."
      exit $ERR
   else
      echo "Got an unexpected result on import, exiting (166)."
      exit 166
   fi
fi
STR=${STR:`expr index "$STR" :`}
STR=${STR:0:${#STR}-1}
echo "Disk image is imported as '$STR'".
echo '------------------------------'

echo "Attaching imported disk '$STR' to VM $1:"
CMD="qm set $VMID --$SCSI $STR,ssd=1,discard=on,iothread=1"
echo "[$CMD]"
RES=$(exec $CMD 2>&1)
ERR=$?
if [[ $ERR -ne 0 ]]; then
   echo "$RES"
   echo
   echo "Error on attaching disk ($ERR), exiting."
   exit $ERR
fi
echo "Disk is attached to VM $VMID as Hard Disk ($SCSI)."

if [[ $BOOT == "TRUE" ]]; then

echo '------------------------------'

echo "Setting the attached disk on $SCSI as the only boot device:"
CMD="qm set $VMID --boot order=$SCSI"
echo "[$CMD]"
RES=$(exec $CMD 2>&1)
ERR=$?
if [[ $ERR -ne 0 ]]; then
   echo "$RES"
   echo
   echo "Error on setting up boot device ($ERR), exiting."
   exit $ERR
fi
echo "Hard Disk ($SCSI) is set as the only bootable device."

fi

echo '------------------------------'

echo "New SCSI disk and boot order config for VM $VMID:"
RES=$(qm config 999 | grep -E scsi[0-9]+:)
echo "$RES"
RES=$(qm config 999 | grep "boot: order=")
echo "$RES"
echo '------------------------------'

echo "Job done: new disk '$STR' as [Hard Disk ($SCSI)] on VM $VMID."
exit 0
