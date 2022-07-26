#!/bin/bash

# Color displays
. ./inc/colors.sh

# Basic requirements

. ./inc/requirements.sh

verbose "Setting up PetaSAN repository"

cat > /etc/apt/sources.list <<-EOM
# main
deb http://archive.ubuntu.com/ubuntu/ focal main
deb http://archive.ubuntu.com/ubuntu/ focal-updates main
deb http://archive.ubuntu.com/ubuntu/ focal-security main

# universe
deb http://archive.ubuntu.com/ubuntu/ focal universe
deb http://archive.ubuntu.com/ubuntu/ focal-updates universe
deb http://archive.ubuntu.com/ubuntu/ focal-security universe
EOM

verbose "Installing wget and other necessities"
apt update
apt -y dist-upgrade
apt install -y wget curl apt-transport-https python3-paramiko python3-pyinotify

cat > /etc/apt/sources.list.d/petasan.list <<-EOM
# PetaSAN updates
deb http://archive.petasan.org/repo_v3/ petasan-v3 updates
EOM

cat > /etc/apt/preferences.d/90-petasan <<-EOM
Package: *
Pin: release o=PetaSAN
Pin-Priority: 700
EOM

verbose "Addding PetaSAN repo key"

wget -qO - http://archive.petasan.org/repo/release.asc | apt-key add -

verbose "Installing PetaSAN kernel and utilities and updating all installed packages"


apt -y -o Dpkg::Options::="--force-overwrite" install ceph-petasan cpupower linux-image-petasan petasan-firmware targetcli-fb lvm2 grub2 python3-ceph-argparse python3-ceph-common python3-ceph python3-cephfs python3-consul python3-rados python3-rbd python3-rgw python3-rtslib-fb radosgw rbd-fuse rbd-mirror rbd-nbd

verbose "Setting PetaSAN kernel as default"
update-grub

verbose "Adding kernel modules"

cat > /etc/modules <<-EOM
# /etc/modules: kernel modules to load at boot time.
#
# This file contains the names of kernel modules that should be loaded
# at boot time, one per line. Lines beginning with "#" are ignored.

configfs
rbd single_major=Y
target_core_mod
target_core_rbd
iscsi_target_mod
EOM

verbose "Copying scripts to /usr/local/bin"
mkdir /etc/ceph
chmod +x scripts/*
cp -a scripts/* /usr/local/bin
systemctl enable rbdmap
chmod +x stage2.sh

warning "Bootstrap complete. Please reboot this server and run the 'stage2.sh' script to continue."