# ProxmoxStuff
Proxmos scripts and howtos

1. __[PVE Disk migration](/pve-add-disk//pve-add-disk.sh)__ ([ReadMe](/pve-add-disk/README.md)): script to import a qemu-compatible disk image to the selected storage as qcow2 and attach it to the desired VM.
2. __[PVE Host backup to PBS](/pbs-host-backup)__: systemd service & timer to make full backup ov PVE root (with importaint includes/excludes). Start with `systemctl enable --now pbsrootbackup.timer`
3. __[PVE suspend on UPS low battery](/pve-stop-resume)__: scripts to use with UPS management: hybernate/stop VMs and prepare to incorrect shutdown (flush and disable write cache); resume VMs/restore write cache.
