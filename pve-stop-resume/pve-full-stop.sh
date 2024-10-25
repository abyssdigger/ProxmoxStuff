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

echo "== Stopping scheduler, corosync and interactive services... ===================="

log_command "pvescheduler stop"

for srv in corosync pveproxy pvedaemon pvestatd; do
	log_command "systemctl stop $srv"
done

echo "== Suspending/shutdowning/stopping(on error) VMs... ============================"

VMLIST=$(qm list --full | grep running)
echo "$VMLIST"
echo "$VMLIST" | while read -r f1 f2 f3 f4 f5 f6; do 
	if [[ ! "$f1" == "" ]]; then 
		echo "[VM#$f1]-----------------------------------"
		log_command "pgrep -f 'task .*:vzdump:$f1:.*' |  xargs -r kill" "...Kill backup tasks (if any)" "suppress"
		log_command "qm unlock $f1" "........Unlock"

		NEVER_SUSPEND_TAG=$(qm config $f1 | grep -E '^tags: *(|.+;)never-suspend(|;.+)$')
		if [[ "$NEVER_SUSPEND_TAG" ]]; then
			log_command "qm shutdown $f1" "SHUTDOWN: "; res=$?
		else
			log_command "qm suspend $f1 --todisk" "HYBERNATE: "; res=$?
		fi
		if [[ "$res" -ne 0 ]]; then
			log_command "qm stop $f1 -overrule-shutdown 1" "ERROR(STOP): "; res=$?
		fi
	fi;
done

echo "== Stopping pve main services... ==============================================="

for srv in pve-firewall pve-ha-crm pve-ha-lrm pve-cluster vz qemu-server; do
	log_command "systemctl stop $srv"
done

echo "== Setting write cache to 0%... ================================================"
log_command "echo 0 | tee /proc/sys/vm/dirty_ratio" "WRITE-CACHE-DISABLE: "

echo "== Done ========================================================================"
