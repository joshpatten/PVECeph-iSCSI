#!/bin/bash

# Color displays
. ./inc/colors.sh

# Basic requirements

. ./inc/requirements.sh

echo "Is this the first server or an additional server? Enter 1 for first, 2 for additional"
read servernum

if [ .$servernum = .'1' ]; then
	echo "First server selected. This will copy existing Ceph configuration from Proxmox and set up iSCSI cluster. Continue (Y/N)?"
	read contq
	if [ .$contq = .'Y' ] || [ .$contq = .'y' ]; then 
		verbose "Continuing with installation"
	else
		warning "Installation cancelled!"
		exit 0
	fi
elif [ .$servernum = .'2' ]; then
	verbose "Additional server selected"
else
	error "Bad entry, please select 1 or 2."
	exit 3
fi

if [ .$servernum = .'1' ]; then
	echo "Please enter the IP address of one of the servers in your Proxmox cluster:"
	read proxmoxip
	echo "The IP address you provided is: ${proxmoxip}"
	echo "Is this correct? (Y/N):"
	read correctip
	if [ .$correctip = .'Y' ] || [ .$correctip = .'y' ]; then
		verbose "Using IP address ${proxmoxip} to connect to Proxmox"
	else
		error "Please enter the correct IP address."
		exit 3
	fi
	verbose "Creating SSH key."
	ssh-keygen -t rsa -b 4096 -m PEM -C root@`hostname` -q -P "" -f /root/.ssh/id_rsa
	warning "You will need to copy the text in between the ------------ markers into the file /root/.ssh/authorized_keys on server ${proxmoxip}, otherwise you will have to enter the root password every time a command is run"
	echo
	warning "------------"
	cat /root/.ssh/id_rsa.pub
	warning "------------"
	echo "When you have added this text to the file /root/.ssh/authorized_keys on server ${proxmoxip}, press Enter to continue"
	read placeholder
	warning "Please accept the connection by typing 'yes' and pressing Enter"
	ssh root@${proxmoxip} "hostname"
	err_check $?
	verbose "Copying ceph configuration from ${proxmoxip}"
	cat > /usr/local/etc/proxmoxip <<-EOM
${proxmoxip}
EOM
	cephsync
	cat > /etc/cron.hourly/cephsyncer <<-EOM
#!/bin/sh
/usr/local/bin/cephsync
	EOM
	chmod +x /etc/cron.hourly/cephsyncer
	sed -i /etc/ssh/sshd_config -e "s:#PermitRootLogin:PermitRootLogin:"
	systemctl restart sshd
else
	echo "Please enter the IP address of the primary iSCSI server:"
	read iscsiip
	echo "The IP address you provided is: ${iscsiip}"
	echo "Is this correct? (Y/N):"
	read correctip
	if [ .$correctip = .'Y' ] || [ .$correctip = .'y' ]; then
		verbose "Using IP address ${iscsiip} to connect to primary iSCSI server"
	else
		error "Please enter the correct IP address."
		exit 3
	fi
	verbose "Creating SSH key."
	ssh-keygen -t rsa -b 4096 -m PEM -C root@`hostname` -q -P "" -f /root/.ssh/id_rsa
	warning "You will need to copy the text in between the ------------ markers into the file /root/.ssh/authorized_keys on server ${iscsiip}, otherwise you will have to enter the root password every time a command is run"
	echo
	warning "------------"
	cat /root/.ssh/id_rsa.pub
	warning "------------"
	echo "When you have added this text to the file /root/.ssh/authorized_keys on server ${iscsiip}, press Enter to continue"
	read placeholder
	warning "Please accept the connection by typing 'yes' and pressing Enter"
	ssh root@${iscsiip} "hostname"
	err_check $?
	verbose "Clearing any existing ceph or target config"
	rm -r /etc/ceph/*
	rm -r /etc/target/*
fi

verbose "Installing Syncthing"

curl -s https://syncthing.net/release-key.txt | sudo apt-key add -
echo "deb https://apt.syncthing.net/ syncthing release" | tee /etc/apt/sources.list.d/syncthing.list

apt update
apt install -y syncthing

cat > /lib/systemd/system/syncthing.service <<-EOM
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization
Documentation=man:syncthing(1)
After=network.target

[Service]
User=root
Type=simple
ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --logflags=0
Restart=on-failure
RestartSec=1
StartLimitIntervalSec=60
StartLimitBurst=4
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

# Hardening
#ProtectSystem=full
#PrivateTmp=true
#SystemCallArchitectures=native
#MemoryDenyWriteExecute=true
#NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOM

systemctl daemon-reload
systemctl enable syncthing

echo "fs.inotify.max_user_watches=204800" | tee -a /etc/sysctl.conf
echo 204800 > /proc/sys/fs/inotify/max_user_watches

systemctl start syncthing
verbose "Giving syncthing time to iniitalize..."
sleep 10
sed -i /root/.config/syncthing/config.xml -e "s:127\.0\.0\.1:0\.0\.0\.0:"
systemctl stop syncthing
systemctl start syncthing
sleep 5
verbose "Setting up Syncthing shares"
if [ .$servernum = .'1' ]; then
	python3 ./inc/syncsetup.py ${servernum}
else
	python3 ./inc/syncsetup.py ${servernum} ${iscsiip}
fi
verbose "Waiting 30 seconds for file sync"
sleep 30

verbose "Setting up targetrestore service"
targetcli-fb set global auto_add_default_portal=false
cat > /lib/systemd/system/targetrestore.service <<-EOM
[Unit]
Description=Restore iSCSI targets
After=network-online.target ceph.target rbdmap.service
Wants=network-online.target ceph.target rbdmap.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-/usr/bin/targetcli-fb restoreconfig /etc/target/saveconfig.json clear_existing=true
ExecReload=-/usr/bin/targetcli-fb restoreconfig /etc/target/saveconfig.json clear_existing=true
ExecStop=/usr/bin/targetcli-fb clearconfig confirm=true

[Install]
WantedBy=multi-user.target

EOM

systemctl daemon-reload
systemctl enable targetrestore
systemctl start targetrestore

cat > /lib/systemd/system/targetwatch.service <<-EOM
[Unit]
Description=TargetWatch Service
After=network.target targetrestore.service

[Service]
Type=Simple
ExecStart=/usr/local/bin/targetwatch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target

EOM

cat > /lib/systemd/system/rbdmapwatch.service <<-EOM
[Unit]
Description=RBDMap Watch Service
After=network.target rbdmap.service

[Service]
Type=Simple
ExecStart=/usr/local/bin/rbdmapwatch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target

EOM

systemctl daemon-reload
systemctl enable targetwatch
systemctl enable rbdmapwatch
systemctl start targetwatch
systemctl start rbdmapwatch

verbose "Setup complete! You may now use targetcli-fb to configure your iSCSI targets."
warning "NOTE: Please use /etc/ceph/rbdmap file to add RBD devices instead of the RBD command, so that these RBD devices are mapped on all hosts!"
warning "NOTE: Please remember to add **ALL** iSCSI target IP addresses when configuring portals in targetcli-fb. DO NOT use 0.0.0.0 or the targets will not appear when querying from an initiator!"