# PVECeph-iSCSI
This project bootstraps an Ubuntu 20.04 instance to provide iSCSI access to Ceph

This project utilizes a custom kernel built by the [PetaSAN project](https://www.petasan.org/) which allows for full iSCSI capabilities to be distributed to Windows Clusters, VMWare instances, etc.

This project also utilizes [Syncthing](https://syncthing.net/) to ensure iSCSI configuration is consistent across nodes when a configuration change is made with [targetcli-fb](https://github.com/open-iscsi/targetcli-fb)
