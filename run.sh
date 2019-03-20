#!/bin/bash
#
# Author: Alberto Planas <aplanas@suse.com>
#
# Copyright 2019 SUSE LINUX GmbH, Nuernberg, Germany.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -e

DIR="$(cd "$(dirname "$0")"; pwd -P)"
LOG="$DIR/run.log"

BLACK="\033[0;30m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"
BRIGHT_BLACK="\033[1;30m"
BRIGHT_RED="\033[1;31m"
BRIGHT_GREEN="\033[1;32m"
BRIGHT_YELLOW="\033[0;33m"
BRIGHT_BLUE="\033[0;34m"
BRIGHT_MAGENTA="\033[0;35m"
BRIGHT_CYAN="\033[0;36m"
BRIGHT_WHITE="\033[0;37m"
RESET="\033[0m"

function error_report  {
    echo -e "${RED}ERROR${RESET} on line $1"
}

trap 'error_report $LINENO' ERR

function exist_iso {
    # Echo 0 if the ISO exist, 2 if do not exits
    ls ISO-openSUSE-Tumbleweed*.iso &> /dev/null
    echo "$?"
}

function reset_iso {
    # Download the last ISO image the includes the salt-minion
    local reset=$1

    [ "$(exist_iso)" = "0" -a "$reset" = "false" ] && return
    [ "$(exist_iso)" = "0" ] && rm ISO-openSUSE-Tumbleweed*.iso

    echo -e "${GREEN}DOWNLOADING${RESET} ISO image from home:aplanas:Images:test-image-iso"

    osc getbinaries home:aplanas:Images test-image-iso images x86_64 >>"$LOG" 2>&1
    mv binaries/*.iso .
    rm -fr binaries
}

function reset_qcow2 {
    # Create a QCOW2 image for the node
    local reset="$1"
    local name="$2"
    local node="$3"
    local size="$4" || "24G"

    local fname="${name}-node${node}.qcow2"

    [ -f "$fname" -a "$reset" = "false" ] && return
    [ -f "$fname" ] && rm "$fname"

    echo -e "${GREEN}CREATING${RESET} QCOW2 image $fname with $size"

    qemu-img create -f qcow2 "$fname" "$size" >>"$LOG" 2>&1
}

function reset_bios {
    # Download the last version of OVMF
    local reset=$1

    [ -f "ovmf-x86_64-code.bin" -a "$reset" = "false" ] && return
    [ -f "ovmf-x86_64-code.bin" ] && rm ovmf-x86_64-code.bin ovmf-x86_64-vars.bin

    echo -e "${GREEN}DOWNLOADING${RESET} OVMF firmware from Virtualization:ovmf"

    osc getbinaries Virtualization ovmf openSUSE_Factory x86_64 >>"$LOG" 2>&1
    cd binaries
    unrpm qemu-ovmf-x86_64*.noarch.rpm >>"$LOG" 2>&1
    cd ..
    mv binaries/usr/share/qemu/ovmf-x86_64-code.bin binaries/usr/share/qemu/ovmf-x86_64-vars.bin .
    rm -fr binaries
}

function stop_salt_master {
    # Stop the salt-master service
    echo -e "${GREEN}STOPPING${RESET} salt-master"

    deactivate &> /dev/null || true
    pkill -9 salt-master || true
    sleep 5
    if pgrep -x "salt-master" > /dev/null; then
	echo -e "${RED}ERROR${RESET} salt-master cannot be stoped, please stop it manually"
	exit 1
    fi
}

function start_salt_master {
    # Start the salt-master service
    echo -e "${GREEN}STARTING${RESET} salt-master"

    deactivate &> /dev/null || true
    export PYTHONWARNINGS="ignore"
    source venv/bin/activate
    salt-master -c venv/etc/salt &
}

function reset_salt_master {
    # Install and configure salt-master inside a venv
    local reset=$1

    [ -d "venv" -a "$reset" = "false" ] && return
    # Before replacing the venv we stop salt-master
    stop_salt_master
    [ -d "venv" ] && rm -fr venv

    echo -e "${GREEN}DOWNLOADING${RESET} salt-master inside a venv"

    # Install salt-master
    python3 -mvenv venv
    source venv/bin/activate
    pip install --upgrade pip >>"$LOG" 2>&1
    pip install cherrypy ws4py salt >>"$LOG" 2>&1 || (echo "${RED}ERROR${RESET} installing salt"; exit 1)

    # Configure salt-master
    [ -d "salt-master" ] && rm -fr salt-master

    echo -e "${GREEN}CONFIGURING${RESET} salt-master"

    mkdir -p venv/etc/salt/pki/{master,minion} \
	  venv/etc/salt/autosign_grains \
	  venv/var/cache/salt/master/file_lists/roots \
	  venv/var
    cat <<EOF > venv/etc/salt/master
root_dir: $(pwd)/venv
log_level: error
autosign_grains_dir: /etc/salt/autosign_grains
file_roots:
  base:
    - $(pwd)/srv/salt
pillar_roots:
  base:
    - $(pwd)/srv/pillar
EOF

    # Generate UUIDs for autosign
    echo -e "${GREEN}GENERATING${RESET} UUIDs for autosign"

    for i in $(seq 0 9); do
	echo $(uuidgen --md5 --namespace @dns --name http://opensuse.org/$i)
    done > venv/etc/salt/autosign_grains/uuid
}

function stop_salt_api {
    # Stop the salt-api service
    echo -e "${GREEN}STOPPING${RESET} salt-api"

    pkill -9 salt-api || true
    sleep 1
    if pgrep -x "salt-api" > /dev/null; then
	echo -e "${RED}ERROR${RESET} salt-api cannot be stoped, please stop it manually"
	exit 1
    fi
}

function start_salt_api {
    # Start the salt-api service
    echo -e "${GREEN}STARTING${RESET} salt-api"

    deactivate &> /dev/null || true
    export PYTHONWARNINGS="ignore"
    source venv/bin/activate
    salt-api -c venv/etc/salt &
}

function reset_salt_api {
    # Configure salt-api inside a venv
    local reset=$1

    echo -e "${GREEN}CONFIGURING${RESET} salt-api"

    mkdir -p venv/etc/salt/master.d
    cat <<EOF > venv/etc/salt/master.d/salt-api.conf
rest_cherrypy:
  port: 8000
  debug: no
  disable_ssl: yes
  # ssl_crt: $(pwd)/venv/etc/ssl/server.crt
  # ssl_key: $(pwd)/venv/etc/ssl/server.key
EOF

    mkdir -p venv/etc/salt/master.d
    cat <<EOF > venv/etc/salt/master.d/eauth.conf
external_auth: 
  file:
    ^filename: $(pwd)/venv/etc/user-list.txt
    salt:
      - .*
      - '@wheel'
      - '@runner'
      - '@jobs'
EOF

    echo 'salt:linux' > venv/etc/user-list.txt
}

function reset_yomi {
    # Reset the Yomi states and pillars
    local reset=$1

    [ -d "srv" -a "$reset" = "false" ] && return
    [ -d "srv" ] && rm -fr srv

    echo -e "${GREEN}DOWNLOADING${RESET} Yomi"

    git clone --depth 1 https://github.com/openSUSE/yomi srv >>"$LOG" 2>&1

    # Clean the top.sls state and the pillars
    rm srv/salt/top.sls
    rm srv/pillar/*
}

function reset_yomi_demo {
    # Reset the Yomi pillars for the demo
    local reset=$1

    [ -f "srv/salt/top.sls" -a "$reset" = "false" ] && return
    if [ -f "srv/salt/top.sls" ]; then
	rm srv/salt/top.sls
	rm srv/pillar/*
    fi

    echo -e "${GREEN}GENERATING${RESET} Yomi pillars"

    cat <<EOF > srv/salt/top.sls
base:
  '00:00:00:*':
    - installer
EOF

    cat <<EOF > srv/pillar/top.sls
base:
  '00:00:00:11:11:11':
    - node1

  '00:00:00:22:22:22':
    - node2
EOF

    cat <<EOF > srv/pillar/node1.sls
config:
  kexec: yes
  snapper: yes
  grub2_theme: yes

partitions:
  config:
    label: gpt
    alignment: 1
  devices:
    /dev/sda:
      partitions:
        - number: 1
          size: 4
          type: boot
        - number: 2
          size: 20000
          type: linux
        - number: 3
          size: 500
          type: swap

filesystems:
  /dev/sda2:
    filesystem: btrfs
    mountpoint: /
    subvolumes:
      prefix: '@'
      subvolume:
        - path: home
        - path: opt
        - path: root
        - path: srv
        - path: tmp
        - path: usr/local
        - path: var
          copy_on_write: no
        - path: boot/grub2/i386-pc
          archs: ['i386', 'x86_64']
        - path: boot/grub2/x86_64-efi
          archs: ['x86_64']
  /dev/sda3:
    filesystem: swap

bootloader:
  device: /dev/sda

software:
  repositories:
    repo-oss: "http://download.opensuse.org/tumbleweed/repo/oss"
  packages:
    - patterns-base-base
    - kernel-default

users:
  - username: root
    password: "\$1\$wYJUgpM5\$RXMMeASDc035eX.NbYWFl0"
EOF

    cat <<EOF > srv/pillar/node2.sls
config:
  kexec: yes
  snapper: yes
  grub2_theme: yes

partitions:
  config:
    label: gpt
    alignment: 1
  devices:
    /dev/sda:
      partitions:
        - number: 1
          size: 256
          type: efi
        - number: 2
          size: 20000
          type: lvm
    /dev/sdb:
      partitions:
        - number: 1
          size: 20000
          type: lvm

lvm:
  system:
    vgs:
      - /dev/sda2
      - /dev/sdb1
    lvs:
      - name: swap
        size: 2000M
      - name: root
        size: 10000M
      - name: home
        size: 10000M

filesystems:
  /dev/sda1:
    filesystem: vfat
    mountpoint: /boot/efi
  /dev/system/swap:
    filesystem: swap
  /dev/system/root:
    filesystem: btrfs
    mountpoint: /
    subvolumes:
      prefix: '@'
      subvolume:
        - path: opt
        - path: root
        - path: srv
        - path: tmp
        - path: usr/local
        - path: var
          copy_on_write: no
        - path: boot/grub2/i386-pc
        - path: boot/grub2/x86_64-efi
  /dev/system/home:
    filesystem: xfs
    mountpoint: /home

bootloader:
  device: /dev/sda

software:
  repositories:
    repo-oss: "http://download.opensuse.org/tumbleweed/repo/oss"
  packages:
    - patterns-base-base
    - kernel-default

users:
  - username: root
    password: "\$1\$wYJUgpM5\$RXMMeASDc035eX.NbYWFl0"
EOF
}


usage="$(basename "$0") [-h] [-c] [-f] [-m] -- Run a Yomi demo for 2 nodes

where:
    -h  show this help text
    -c  clean the qcow2 images
    -f  full clean, including the ISO image
    -m  skip the test for salt-master"

qcow2_clean=false
full_clean=false
check_salt_master=true
while getopts ':hcf' option; do
    case "$option" in
	h)
	    echo "$usage"
	    exit
	    ;;
	c)
	    qcow2_clean=true
	    ;;
	f)
	    qcow2_clean=true
	    full_clean=true
	    ;;
	m)
	    check_salt_master=false
	    ;;
	\?)
	    echo "Invalid option: -$OPTARG" >&2
	    echo "$usage" >&2
	    exit 1
	    ;;
    esac
done

echo "Starting demo" >>"$LOG" 2>&1

# If we reset the ISO or ISO is not found, download it
reset_iso "$full_clean"

# Node 1 -- 1 HD -- BIOS
reset_qcow2 "$qcow2_clean" "hda" "1" "24G"

# Node 2 -- 2 HD -- UEFI
reset_qcow2 "$qcow2_clean" "hda" "2" "24G"
reset_qcow2 "$qcow2_clean" "hdb" "2" "24G"

# Get the OVMF firmware
reset_bios "$full_clean"

# Setup salt-master
reset_salt_master "$full_clean"

# Configure salt-api
reset_salt_api "$full_clean"

# Stop and start the services in order
stop_salt_api
stop_salt_master
start_salt_master
sleep 30
start_salt_api

# Put in place the Yomi code
reset_yomi "$full_clean"

# Also put in place the pillars for the demo
reset_yomi_demo "$full_clean"

# Check if the salt-master is running
if ! pgrep -x "salt-master" > /dev/null; then
    echo "salt-master is not running locally, please start the service"
    exit 1
fi

echo -e "${GREEN}CLEANING${RESET} old salt-minion keys"

salt-key -c venv/etc/salt -yD >>"$LOG" 2>&1

echo -e "${GREEN}BOOTING${RESET} node 1 and node 2 VMs"

# Launch node 1
qemu-system-x86_64 -m 1024 -enable-kvm \
   -netdev user,id=net0,hostfwd=tcp::10022-:22 \
   -device e1000,netdev=net0,mac=00:00:00:11:11:11 \
   -cdrom ISO*.iso \
   -hda hda-node1.qcow2 \
   -boot d &

# Launch node 2
qemu-system-x86_64 -m 1024 -enable-kvm \
   -netdev user,id=net0,hostfwd=tcp::10023-:22 \
   -device e1000,netdev=net0,mac=00:00:00:22:22:22 \
   -cdrom ISO*.iso \
   -hda hda-node2.qcow2 \
   -hdb hdb-node2.qcow2 \
   -drive if=pflash,format=raw,unit=0,readonly,file=./ovmf-x86_64-code.bin \
   -drive if=pflash,format=raw,unit=1,file=./ovmf-x86_64-vars.bin \
   -boot d &

wait ${!}
