# PVECeph-iSCSI
This project bootstraps an Ubuntu 20.04 instance to provide iSCSI access to Ceph

This project utilizes a custom kernel built by the [PetaSAN project](https://www.petasan.org/) which allows for full iSCSI capabilities to be distributed to Windows Clusters, VMWare instances, etc.

This project also utilizes [Syncthing](https://syncthing.net/) to ensure iSCSI configuration is consistent across nodes when a configuration change is made with [targetcli-fb](https://github.com/open-iscsi/targetcli-fb)

## Setup
Setup is done in 2 stages: Bootstrapping, and node configuration.

During the bootstrapping phase, the PetaSAN kernel and other utilities will be installed to facilitate the node configuration stage.

To start the bootstrapping phase you'll need to download this repo and run the `bootstrap.sh` script.

First, you need to ensure you're running as root:
    sudo -s

Then run the following commands:

    cd ~
    apt -Y install git
    git clone https://github.com/joshpatten/PVECeph-iSCSI.git
    cd PVECeph-iSCSI
    chmod +x bootstrap.sh
    ./bootstrap.sh

Once the bootstrap is complete you will need to reboot the server.

After the server has rebooted you can begin stage 2:

    cd ~/PVECeph-iSCSI
    ./stage2.sh

You will be prompted to select if this is the first server you are setting up, or if it is an additional server.

### First Server
If this is the first server you will be setting up then stage 2 will connect to your Proxmox cluster to pull the necessary Ceph configuration so that the iSCSI servers can access RBDs.

You will need to copy the SSH public key to the Proxmox host you specify when prompted. The on-screen instructions will tell you exactly what to do.

### Additional Servers
If this is an additional server then stage 2 will connect to the first iSCSI server to pull existing iSCSI configuration in.

You will need to copy the SSH public key to the first iSCSI server when prompted. The on-screen instructions will tell you exactly what to do.
