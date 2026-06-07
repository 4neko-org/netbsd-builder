# NetBSD Builder

<img src="https://cdn.4neko.org/freya/vm_netbsd.webp" width="250"/>


This project builds a QEMU VM Image for the [freya](https://codeberg.org/4neko/freya)

This project is based on
[cross-platform-actions/netbsd-builder](https://github.com/cross-platform-actions/netbsd-builder)
GitHub action. The image contains a standard NetBSD installation without any
X components. It will install the following distribution sets:

* Kernel (GENERIC)
* Kernel modules
* Base
* Configuration files
* Compiler tools
* X11 base and clients
* X11 programming
* X11 configuration
* X11 fonts
* X11 servers

In addition to the above file sets, the following packages are installed as well:

* bash
* curl
* pkgin
* rsync
* sudo
* openssl
* git

The follwoing packages are built:
* freyashell

BIOS:
EFI OVMF.fd


Disk layout:
```text
/dev/dk1 on / type ffs (read-only, local)
tmpfs on /var type tmpfs (local)
tmpfs on /tmp type tmpfs (local)
kernfs on /kern type kernfs (local)
ptyfs on /dev/pts type ptyfs (local)
procfs on /proc type procfs (local)
tmpfs on /var/shm type tmpfs (local)
tmpfs on /home/freya/.ssh type tmpfs (local)
/dev/ld1a on /home/freya/storage type ffs (local)
```

Attached images:
```text
DISK1:
An image of the disk formatted as msdosfs with the following directory layout:

/KEYS - authorized_keys which will be copied to /home/freya/.ssh/


DISK2:
An image of the disk non-formatted, large enough (to fit the code and building) where 
all the files received over freyashell will be installed. The VM will format and mount
the disk manually.
```

!!! Make sure that both disks are attached to VM because each is strictly binded by its order. 
Even if you don't need DISK1 i.e you will use default passwords, attach a dummy disk which is not 
necessary to format.

The `/` is mounted as read-only. The `freya's` homedir is also read-only.

Except for the root user, there's one additional user, `freya`, which is the
user that will be running the [freyashell](https://codeberg.org/4neko/freyashell). 
This user can use `sudo` with a password.

The default password for the `root` is `runner`.

## Architectures and Versions

The following architectures and versions are supported:

| Version | x86-64 | ARM64 |
|---------|--------|-------|
| 10.1    | ✓      | ✓     |
| 10.0    | ✓      | ✓     |

## Building Locally

### Prerequisite

####  [UEFI firmware](https://github.com/tianocore/edk2)

This needs to be located at `resources/ovmf.fd`. Copy the `OVMF.fd` for it's
install location to `resources/ovmf.fd`.

* **Ubuntu** - Install the [`ovmf`](https://packages.ubuntu.com/jammy/ovmf) package.
* **Fedora** - Install the [`edk2-ovmf`](https://fedora.pkgs.org/34/fedora-x86_64/edk2-ovmf-20200801stable-4.fc34.noarch.rpm.html) package.
* **macOS** - Copy the `OVMF.fd` file from a Linux machine

#### Other

* [Packer](https://www.packer.io) 1.7.2 or later
* [QEMU](https://qemu.org)

### Building

1. Clone the repository:
    ```
    git clone https://github.com/4neko-org/netbsd-builder
    cd netbsd-builder
    ```
2. If you running it first time, probably you need to run
    ```
    packer init openbsd.pkr.hcl
    ```
3. Run `build.sh` to build the image:

    ```
    ./build.sh <version> <architecture>
    ```

    Where `<version>` and `<architecture>` are the any of the versions or
    architectures available in the above table.

    ```
    ./build.sh <version> <architecture> -var checksum=<checksum>
    ```

    On non-macOS platforms the `display` variable needs to be overridden by
    specifying `-var display=gtk` or `-var display=sdl` at the end when invoking
    the `build.sh` script:

    ```
    ./build.sh <version> <architecture> -var display=gtk
    ```

    To enable the hardware acceleration during building run

    ```
    ./build.sh <version> <architecture> -var display=gtk -var cpu_type=host
    ```

    Example:

    ```
    ./build.sh 10.1 x86-64 -var display=gtk -var cpu_type=host
    ```

The above command will build the VM image and the resulting disk image will be
at the path: `output/netbsd-10.1-x86-64.qcow2`.

## Additional Information

This VM can be shut down without any gracefull shutdown as the disk is running in 
read-only mode.

At startup, the image will look for a second hard drive (as described above). 
If it presents and it
contains a file named `keys` at the root, it will install this file as the
`authorized_keys` file for the `runner` user. The disk is expected to be
formatted as FAT32. This is used as an alternative to a shared folder between
the host and the guest, since this is not supported by the xhyve hypervisor.
FAT32 is chosen because it's the only filesystem that is supported by both the
host (macOS) and the guest (NetBSD) out of the box.

Also, at startup, the OS will look for the third hard drive (as described above).
If it presents, an OS will `fdisk` the image and invoke `newfs` on the disk
erasing everything which was installed previously. This disk image is a workdisk 
where writing is allowed.


The VM needs to be configured with the `virtio-net` network device. The disk needs to
be configured with the GPT partitioning scheme. And the VM needs to be configured
to use UEFI. All this is required for the VM image to be able to run using the
xhyve hypervisor.

The qcow2 format is chosen because unused space doesn't take up any space on
disk, it's compressible and easily converts the raw format.

## Mounting / altering image without rebuilding

If it is required to alter something in the image (instead of rebuilding it), 
the following should be performed:

1. Log into the VM

2. Run the follwoing

```shell
# mount root as RW
mount -uw /

# edit the fstab
vi /etc/fstab

# set the root mount from 'ro' to 'rw' like below
NAME=2537c69f-632c-4a9d-b2e0-blabla		/	ffs	ro		 1 1
# to
NAME=2537c69f-632c-4a9d-b2e0-blabla		/	ffs	rw		 1 1

# comment the /var in order to disable tmpfs mounting like below
# tmpfs /var tmpfs   rw,-m1777,-sram%25

reboot

### DO changes

```

3. After making all necessary changes do the following:

```shell
# Create new image of /var
cd /

tar -cvzf var-image.tar.gz var

# in etc/fstab

# uncomment tmpfs /var line
tmpfs /var tmpfs   rw,-m1777,-sram%25

# change the RW to RO
NAME=2537c69f-632c-4a9d-b2e0-blabla		/	ffs	rw		 1 1
# to
NAME=2537c69f-632c-4a9d-b2e0-blabla		/	ffs	ro		 1 1

# reboot machine or shutdown
reboot
```

## Startup example

```
/usr/bin/qemu-system-x86_64 \
    -machine type=q35,accel=hvf:kvm:tcg \
    -cpu host \
    -smp 2 \
    -m 4G \
    -device e1000,netdev=user.0,addr=0x03 \
    -netdev user,id=user.0,hostfwd=tcp::65500-:22 \
    -display sdl \
    -monitor none \
    -serial file:/tmp/NetBSD_10.1_65500.txt \
    -boot strict=off \
    --bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -device virtio-blk-pci,drive=drive0,bootindex=0 \
    -drive if=none,file=/tmp/netbsd-10.1-x86-64.qcow2,id=drive0,cache=unsafe,discard=ignore \
    -device virtio-scsi-pci,drive=drive1,bootindex=1 \
    -drive if=none,file=/tmp/test0.qcow2,id=drive1,cache=unsafe,discard=ignore,format=qcow2 \
    -device virtio-scsi-pci,drive=drive2,bootindex=2 \
    -drive if=none,file=/tmp/test1.qcow2,id=drive2,cache=unsafe,discard=ignore,format=qcow2
```