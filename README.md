# ProxmoxStuff
Proxmos scripts and howtos

1. __[PVE Disk migration](/pve-add-disk//pve-add-disk.sh)__/[ReadMe](/pve-add-disk/README.md): script to import a qemu-compatible disk image to the selected storage as qcow2 and attach it to the desired VM.
2. __[PVE Host backup to PBS](/pbs-host-backup)__: systemd service & timer to make full backup of the PVE root (with important includes/excludes). Start with `systemctl enable --now pbsrootbackup.timer`
3. __[PVE suspend on UPS low battery](/pve-stop-resume)__: scripts to use with UPS management: hybernate/stop VMs and prepare to incorrect shutdown (flush and disable write cache); resume VMs/restore write cache/adjust VM clock (proxmox doesn't automatically adjust VM's system time after hybernate/resume).
4. __[PVE rename VM](/pve-vm-rename)__/[ReadMe](/pve-vm-rename/README.md): script to correctly and safely change VMID (only ceph and dir storages are supported for now - I'm not using others so unable to test them). Can be run in safe mode (just makes VM and VMID checks and lists commands to rename) or in execute mode (executes all commands to rename VM, but switches to safe mode if any unsupported storage found).
