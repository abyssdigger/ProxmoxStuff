#!/bin/bash

function log_command() { # <command> <prefix> <suppress comand text>
        echo -n "$2"; [[ "$3" == "" ]] && echo -n "[$1]"; echo -n "..."
        OUTPUT=$(eval "$1" 2>&1)
        RES=$?
        if [[ "$RES" -eq 0 ]]; then
                echo "ok."
        else
                echo "error($RES), output:"
                echo "$OUTPUT"
        fi
        return $RES
}

echo "== Restoring write cache parameters... ========================================="
# Search if vm.dirty_ratio is set in /etc/sysctl.conf
DIRTYR=$(sed -n 's/^\s*vm\.dirty_ratio\s*=\s*\([0-9]\{1,2\}\)\s*\(\|#.*\)$/\1/p' /etc/sysctl.conf | sed -n '$p')
if [[ "$DIRTYR" == "" ]]; then 
	DIRTYR=20; # if not - set 20 (default value for vm.dirty_ratio on Proxmox)
else
	echo "Found vm.dirty_ratio=$DIRTYR in /etc/sysctl.conf, using it to set write cache size:"
fi
log_command "sysctl -w vm.dirty_ratio=$DIRTYR" "WRITE-CACHE-ENABLE($DIRTYR): "


echo "== Starting pve main services... ==============================================="

for srv in qemu-server vz pve-cluster pve-ha-lrm pve-ha-crm pve-firewall; do
        log_command "systemctl start $srv"
done


echo "== Resuming/starting VMs... ===================================================="

VMLIST=$(qm list --full | grep stopped)
echo "$VMLIST"
echo "$VMLIST" | while read -r f1 f2 f3 f4 f5 f6; do
        if [[ ! "$f1" == "" ]]; then
                echo "[VM#$f1]-----------------------------------"
		VMCONFIG=$(qm config $f1)
                if [[ "$(grep  -E '^template:[[:space:]]*1[[:space:]]*$' <<< $VMCONFIG)" ]]; then # Template
			echo "VM#$f1 is TEMPLATE, skipping."
			continue
		fi
                if [[ ! "$(grep  -E '^onboot:[[:space:]]*1[[:space:]]*$' <<< $VMCONFIG)" ]]; then # Start on boot is not set
			echo "VM#$f1 is NOT SET TO START ON BOOT, skipping."
			continue
		fi
                log_command "qm unlock $f1" "........Unlock"
                log_command "qm start $f1" "START: "; res=$?
        fi;
done
echo "--------------------------------------------"
qm list --full

echo "== Starting interactive services, scheduler and corosync... ===================="
for srv in pvestatd pvedaemon pveproxy corosync; do
        log_command "systemctl start $srv"
done
log_command "pvescheduler start"

echo "== Done ========================================================================"
