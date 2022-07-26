#!/bin/bash
err_check () {
	case $1 in
		0) ;;
		*) error "Program exiting abnormally with error code $1"; exit $1;
	esac
}

err_check_pass () {
	case $1 in
		0) ;;
		*) warning "$2";
	esac
}

# Ensure root user is installing
if [ .$EUID != .'0' ]; then
	error "You must be root to install, exiting..."
	exit 100
fi

#operating system details
os_name=$(lsb_release -is)
os_codename=$(lsb_release -cs)

#cpu details
cpu_name=$(uname -m)

# Need 64 bit CPU (what year is it?????)
if [ .$cpu_name = .'x86_64' ]; then
	verbose "64 bit CPU detected!"
	if [ .$(grep -o -w 'lm' /proc/cpuinfo | head -n 1) = .'lm' ]; then
		verbose "64 bit OS detected!"
	else
		error "32 bit OS detected. Please install 64 bit OS!"
		exit 3
	fi
else
	error "32 bit CPU detected, please upgrade to hardware that supports 64 bit instructions!"
	exit 3
fi

if [ .$os_name = .'Ubuntu' ]; then
	if [ .$os_codename = .'focal' ]; then
		verbose "${os_name} ${os_codename} (20.04) detected, continuing!"
	else
		error "${os_name} ${os_codename} detected, please use Ubuntu focal (20.04) x86_64!"
		exit 3
	fi
else
	error "${os_name} ${os_codename} detected, please use Ubuntu focal (20.04) x86_64!"
	exit 3
fi