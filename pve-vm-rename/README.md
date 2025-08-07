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

- Only RBD(ceph) and DIR storage types are supported.
- Virtual disks on other storage types like LVM or ZFS should be moved to the new VMID manually (some ideas can be found on this Proxmox forum threads: [Changing VMID of a VM](https://forum.proxmox.com/threads/changing-vmid-of-a-vm.63161) and [How to rename a vm?](https://forum.proxmox.com/threads/how-to-rename-a-vm.9680)).
- Script with `--force` parameter will change VMID so disks on unsupported storages may become inaccessible for VM.

## Algo

1. Checks VM and VMID preconditions:
    - VM's existence (on current node);
    - new ID availability (cluster-wide);
    - if in _execute_ mode - VM's state (stopped);
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

## Examples

### Dry run on stopped VM

```text
# ./pve-vm-rename.sh 490777 490888
Job started: rename VM 490777 to 490888, mode: dry run (list commands to rename VM).
---------------------------------------------------------------------------------------
Check VM and VMID preconditions:
[1] check VM existence: <qm status 490777>: OK.
[2] check new VMID is available (490888 is not in /etc/pve/.vmlist): OK.
---------------------------------------------------------------------------------------
Parse /etc/pve/qemu-server/490777.conf for virtual disks:
> scsi0 cephvm:vm-490777-disk-0: [rbd:cephvm].
> scsi1 local:490777/vm-490777-disk-0.qcow2: [dir:/var/lib/vz/images].
> scsi2 mirror:490777/vm-490777-disk-0.vmdk: [dir:/mnt/mirror/pve/images].
> scsi3 mirror:490777/vm-490777-disk-1.vmdk: [dir:/mnt/mirror/pve/images].
> scsi4 cephxec:vm-490777-disk-0: [rbd:cephecssd-metadata].
> scsi5 cephzec:vm-490777-disk-0: [rbd:cephec-metadata].
---------------------------------------------------------------------------------------
Prepare command list to execute:
> commands to update VMID in config files... OK.
> commands to rename VM files... OK.
> commands to rename dirs named on VM... OK.
---------------------------------------------------------------------------------------
List commands to rename VM:
#### CHECK VM IS STOPPED BEFORE EXECUTION!
#### Rename virtual disk scsi0 [rbd:cephvm]
rbd mv -p cephvm vm-490777-disk-0 vm-490888-disk-0
#### Rename virtual disk scsi1 [dir:local]
mv -f /var/lib/vz/images/490777/vm-490777-disk-0.qcow2 /var/lib/vz/images/490777/vm-490888-disk-0.qcow2
#### Rename virtual disk scsi2 [dir:mirror]
mv -f /mnt/mirror/pve/images/490777/vm-490777-disk-0.vmdk /mnt/mirror/pve/images/490777/vm-490888-disk-0.vmdk
#### Rename virtual disk scsi3 [dir:mirror]
mv -f /mnt/mirror/pve/images/490777/vm-490777-disk-1.vmdk /mnt/mirror/pve/images/490777/vm-490888-disk-1.vmdk
#### Rename virtual disk scsi4 [rbd:cephxec]
rbd mv -p cephecssd-metadata vm-490777-disk-0 vm-490888-disk-0
#### Rename virtual disk scsi5 [rbd:cephzec]
rbd mv -p cephec-metadata vm-490777-disk-0 vm-490888-disk-0
#### VM config - update storage dirs
sed -i 's/\(^scsi[0-9]\+: .\+:\)490777\//\1490888\//g' /etc/pve/qemu-server/490777.conf
#### Pool members - update VM names
sed -i '/^pool:.*/s/\([:,]\)490777\([:,]\)/\1490888\2/g' /etc/pve/user.cfg
#### Backup jobs - update VM names
sed -i '/^[[:space:]]\(vmid \|exclude \)/s/\([ ,]\)490777\(,\|$\)/\1490888\2/g' /etc/pve/jobs.cfg
#### (untested) Replication - update VM names
sed -i '/^.\+: 490777-[0-9]\+$/s/\(: \)490777\(-[0-9]\+$\)/\1490888\2/p' /etc/pve/replication.cfg
#### HA config - update VM names
sed -i 's/\(^vm: \)490777/\1490888/g' /etc/pve/ha/resources.cfg
#### VM config - update disk names
sed -i '/^scsi[0-9]\+: .*:/s/vm-490777\(-disk-\)/vm-490888\1/g' /etc/pve/qemu-server/490777.conf
#### Rename firewall config file /etc/pve/firewall/490777.fw
mv -f /etc/pve/firewall/490777.fw /etc/pve/firewall/490888.fw
#### Rename VM config file /etc/pve/qemu-server/490777.conf
mv -f /etc/pve/qemu-server/490777.conf /etc/pve/qemu-server/490888.conf
#### Rename dir /var/lib/vz/images/490777
mv -f /var/lib/vz/images/490777 /var/lib/vz/images/490888
#### Rename dir /mnt/mirror/pve/images/490777
mv -f /mnt/mirror/pve/images/490777 /mnt/mirror/pve/images/490888
---------------------------------------------------------------------------------------
Job done without any changes (run listed commands manually or use --exec to execute them).
```

### Exec on stopped VM

```text
# qm list
      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID
     15253 pbs-test.tmp         running    32768             32.00 7123
     15254 pve-test.tmp         running    65536             50.00 17319
    490777 TestRename           stopped    4096              32.00 0
# ./pve-vm-rename.sh 490777 490888 --exec
Job started: rename VM 490777 to 490888, mode: execute (run commands to rename VM).
---------------------------------------------------------------------------------------
Check VM and VMID preconditions:
[1] check VM existence: <qm status 490777>: OK.
[2] check new VMID is available (490888 is not in /etc/pve/.vmlist): OK.
[3] check VM status (must be stopped): OK.
---------------------------------------------------------------------------------------
Parse /etc/pve/qemu-server/490777.conf for virtual disks:
> scsi0 cephvm:vm-490777-disk-0: [rbd:cephvm].
> scsi1 local:490777/vm-490777-disk-0.qcow2: [dir:/var/lib/vz/images].
> scsi2 mirror:490777/vm-490777-disk-0.vmdk: [dir:/mnt/mirror/pve/images].
> scsi3 mirror:490777/vm-490777-disk-1.vmdk: [dir:/mnt/mirror/pve/images].
> scsi4 cephxec:vm-490777-disk-0: [rbd:cephecssd-metadata].
> scsi5 cephzec:vm-490777-disk-0: [rbd:cephec-metadata].
---------------------------------------------------------------------------------------
Prepare command list to execute:
> commands to update VMID in config files... OK.
> commands to rename VM files... OK.
> commands to rename dirs named on VM... OK.
---------------------------------------------------------------------------------------
Executing commands to rename VM (exit code will show number of errors on execution):
> Rename virtual disk scsi0 [rbd:cephvm]: OK.
> Rename virtual disk scsi1 [dir:local]: OK.
> Rename virtual disk scsi2 [dir:mirror]: OK.
> Rename virtual disk scsi3 [dir:mirror]: OK.
> Rename virtual disk scsi4 [rbd:cephxec]: OK.
> Rename virtual disk scsi5 [rbd:cephzec]: OK.
> VM config - update storage dirs: OK.
> Pool members - update VM names: OK.
> Backup jobs - update VM names: OK.
> (untested) Replication - update VM names: OK.
> HA config - update VM names: OK.
> VM config - update disk names: OK.
> Rename firewall config file /etc/pve/firewall/490777.fw: OK.
> Rename VM config file /etc/pve/qemu-server/490777.conf: OK.
> Rename dir /var/lib/vz/images/490777: OK.
> Rename dir /mnt/mirror/pve/images/490777: OK.
---------------------------------------------------------------------------------------
Job done with all commands executed successfully.
# qm start 490888
# qm status 490888
status: running
```

### Exec on running VM (incorrect)

```text
# qm list
      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID
     15253 pbs-test.tmp         running    32768             32.00 7123
     15254 pve-test.tmp         running    65536             50.00 17319
    490888 TestRename           running    4096              32.00 3640780
# ./pve-vm-rename.sh 490888 490777 --exec
Job started: rename VM 490888 to 490777, mode: execute (run commands to rename VM).
---------------------------------------------------------------------------------------
Check VM and VMID preconditions:
[1] check VM existence: <qm status 490888>: OK.
[2] check new VMID is available (490777 is not in /etc/pve/.vmlist): OK.
[3] check VM status (must be stopped): ERROR, VM 490888 status: running
```
