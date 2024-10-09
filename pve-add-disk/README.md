# pve-add-disk.sh
Bash [script](pve-add-disk.sh) to import a [qemu/kvm](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines)-compatible disk image to the selected [PVE storage](https://pve.proxmox.com/wiki/Storage) as [qcow2](https://en.wikipedia.org/wiki/Qcow), attach it to the desired VM, set up disk's common used [options](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines#qm_virtual_machines_settings) (**ssd**, **iothread**, **discard**) and make it bootable _(optional)_. 
Uses Proxmox [qm utility](https://pve.proxmox.com/pve-docs/qm.1.html).

Usage: `sudo ./pve-add-disk.sh <vmid> <disk> <storage> [--noboot]`, where:
1. `<vmid>`: The (unique) ID of the VM;
2. `<disk>`: Path to the disk image to import and attach (format has to be supported by qemu-img);
3. `<storage>`: Target storage ID (use `sudo pvesm status` to get list of available storages);
4. `--noboot`: if not set then `<disk>` will be attached to `<vmid>` as the only bootable device.

Algo:
1. Check for VM existance (uses `qm config`) and search for the first free scsiX name in VM's configuration;
2. Import `<disk>` to `<storage>` for VM `<vmid>` (uses `qm importdisk`);
3. Attach disk to VM, i.e. change from unused to attached, like `Add` button in web interface (uses `qm set`);
4. Make an attached disk the only boot device if `--noboot` is not specified (uses `qm set`);
5. Show summary (uses `qm config`).

Examlpe:
```
user@test:$ sudo ./pve-add-disk.sh 999 disk-image.qcow2 pvestorage
vmid    : 999
file    : disk-image.qcow2
storage : pvestorage
Disk will be set as the only bootable device (--noboot is not set)
------------------------------
Checking VM 999 configuration:
[qm config 999]
Disk will be attached to VM 999 as HardDisk (scsi0).
------------------------------
Importing disk image to pve:
[qm importdisk 999 disk-image.qcow2 pvestorage --format qcow2]
importing disk 'disk-image.qcow2' to VM 999 ...
Formatting '/mnt/pve/pvestorage/images/999/vm-999-disk-0.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off preallocation=metadata compression_type=zlib size=133141954560 lazy_refcounts=off refcount_bits=16
transferred 0.0 B of 124.0 GiB (0.00%)
...
transferred 124.0 GiB of 124.0 GiB (100.00%)
Successfully imported disk as 'unused0:pvestorage:999/vm-999-disk-0.qcow2'
Disk image is imported as 'pvestorage:999/vm-999-disk-0.qcow2'.
------------------------------
Attaching imported disk 'pvestorage:999/vm-999-disk-0.qcow2' to VM 999:
[qm set 999 --scsi0 pvestorage:999/vm-999-disk-0.qcow2,ssd=1,discard=on,iothread=1]
Disk is attached to VM 999 as Hard Disk (scsi0).
------------------------------
Setting the attached disk on scsi0 as the only boot device:
[qm set 999 --boot order=scsi0]
Hard Disk (scsi0) is set as the only bootable device.
------------------------------
New SCSI disk and boot order config for VM 999:
scsi0: pvestorage:999/vm-999-disk-0.qcow2,discard=on,iothread=1,size=130021440K,ssd=1
boot: order=scsi0
------------------------------
Job done: new disk 'pvestorage:999/vm-999-disk-0.qcow2' as [Hard Disk (scsi0)] on VM 999.
```
