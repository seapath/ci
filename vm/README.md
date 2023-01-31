# Setup VM

This directory contains the vm_setup.sh script.
This script can be used to setup a VM for testing and usable with the CI.

## Prerequisite

* a Debian 11 VM
* a virtu created user inside the Debian 11 VM

## How to use it

Simply copy the vm_setup.sh inside the VM, run it as root and reboot.

## Network configuration

The script use systemd-networkd to configure the network. It adds a static IP
for all interfaces with a MAC address which begin with 52:54:00:42:ab.

The given IP is 10.0.24.x/24 where x is the MAC address bytes.
