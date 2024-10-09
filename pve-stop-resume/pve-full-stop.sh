#!/bin/bash

pvescheduler stop
systemctl stop corosync
systemctl stop {pveproxy,pvedaemon,pvestatd}
qm list --full
qm list | while read f1 f2 f3 f4 f5 f6; do if [[ "$f3" == "running" ]]; then qm suspend $f1 --todisk; fi; done
systemctl stop pve-firewall
systemctl stop pve-ha-crm
systemctl stop pve-ha-lrm
systemctl stop pve-cluster
umount /mnt/pve/raid5


