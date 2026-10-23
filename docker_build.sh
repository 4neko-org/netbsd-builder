#!/usr/bin/env sh

set -eux

OS_VERSION="$1"; shift
ARCHITECTURE="$1"; shift

#os_name=$(cat /etc/os-release | awk -F '=' '/^NAME/{print $2}' | awk '{print $1}' | tr -d '"')
#
#if [ "$os_name" == "Ubuntu" ]
#then
 #       echo "This is Ubuntu"
  #      

#elif [ "$os_name" == "Fedora" ]
#then
 #       
#else
#        echo "system is $os_name, please update the script!"
#fi


docker run \
    -v $(pwd):/workspace -w /workspace \
    -v /usr/share/edk2/ovmf/OVMF_CODE.fd:/workspace/resources/ovmf.fd \
    -e PACKER_PLUGIN_PATH=/workspace/.packer.d/plugins \
    packer-qemu:latest \
    init netbsd.pkr.hcl

docker run \
    -v $(pwd):/workspace -w /workspace \
    -v /usr/share/edk2/ovmf/OVMF_CODE.fd:/workspace/resources/ovmf.fd \
    --device=/dev/kvm \
    --privileged \
    -e PACKER_PLUGIN_PATH=/workspace/.packer.d/plugins \
    -e PACKER_LOG=1 \
    packer-qemu:latest \
    build \
        -var os_version="$OS_VERSION" \
        -var display=none \
        -var cpu_type=host \
        -var-file "var_files/common.pkrvars.hcl" \
        -var-file "var_files/$ARCHITECTURE.pkrvars.hcl" \
        -var-file "var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl" \
        -var-file "var_files/$OS_VERSION/common.pkrvars.hcl" \
        "$@" \
        netbsd.pkr.hcl