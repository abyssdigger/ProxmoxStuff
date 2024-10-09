#!/bin/bash


mount /dev/sdb1 /mnt/pve/raid5
systemctl start pve-cluster
systemctl start pve-ha-lrm
systemctl start pve-ha-crm
systemctl start pve-firewall
qm list | while read f1 f2 f3 f4 f5 f6; do if [[ ! "$f1" == "9999" ]]; then qm start $f1; fi; done
qm list --full
systemctl start {pveproxy,pvedaemon,pvestatd}
systemctl start corosync
pvescheduler start


