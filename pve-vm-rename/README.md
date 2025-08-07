# pve-vm-rename.sh

Bash [script](pve-vm-rename.sh) to rename Proxmox virtual machine (change VMID) correctly and safely.

## Usage

Basic usage (safe):

```shell
pve-vm-rename.sh <old-vmid> <new-vmid> --exec
```

Supported modes:

- _dry run_ (safe mode - just makes checks and lists commands to rename)
- _execute_ (executes all commands to rename VM if all disks' storages are supported, but switches to _dry run_ mode if any unsupported storage found)$
- _force_ (stays in _execute_ mode in any case).

Run `pve-vm-rename.sh --help` for more information.

## Limitations and cautions

- Only RBD(ceph) and DIR storage types are supported. Virtual disks on other storage types like LVM or ZFS should be moved to the new VMID manually.
- If script is run with `--exec` parameter it will switch to safe mode (dry run) if any disk on unsupported storage detected.
- Script with `--exec-yes` parameter will change VMID so disks on unsupported storages may become inaccessible for VM.

## Algo

1. Checks VM and VMID preconditions:
    - VM's state (exists on current node and stopped);
    - new ID availability (cluster-wide);
1. Discovers VM's hard disks and on each disk:
    - gets info on disk's storages;
    - prepares commands for correct disk binding on VMID change;
1. Prepares commands to changes dir/file names: 
    - ceph and dir storages;
    - firewall rules file;
    - VM config file;
1. Prepares commands updates VMID in configs:
    - VM config;
    - backup jobs;
    - HA config;
    - replication (untested);
    - pool members in user's config;
1. Depending on selected mode (see _Usage_ above) and unsupported storage existence:
    - in _dry run_ mode just lists commands to rename;
    - in _execute_ mode executes all commands to rename VM.
