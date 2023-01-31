#!/bin/bash

# A script to setup a VM for testing
# Must be run inside a Debian 11 VM

# Enable console in serial
systemctl enable serial-getty@ttyS0
systemctl start serial-getty@ttyS0

# Create network file
for n in $(seq 1 254) ; do
cat <<EOF > /etc/systemd/network/00-wired-$n.network
[Match]
MACAddress=52:54:00:42:ab:$(printf '%x' $n)

[Network]
Address=10.0.24.$n/24
EOF
done

systemctl enable systemd-networkd
systemctl disable networking.service
systemctl restart systemd-networkd
# Install curl ca-certificates and gnupg
export DEBIAN_FRONTEND=noninteractive
apt-get purge ifupdown
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg

# Enable Docker and Debian backport repository
curl -s  https://download.docker.com/linux/debian/gpg | apt-key add -

echo "deb http://ftp.fr.debian.org/debian bullseye-backports main contrib non-free" >/etc/apt/sources.list.d/debian-backports.list
echo "deb https://download.docker.com/linux/debian bullseye stable" >  /etc/apt/sources.list.d/docker.list

# Install pakcage
apt-get install -y -t bullseye-backports linux-image-rt-amd64
apt-get install -y \
    cpuset \
    docker-compose \
    docker.io \
    ethtool \
    iperf3 \
    irqbalance \
    chrony \
    rt-tests \
    stress-ng \
    tcpdump \
    wget

# Enable KVM-PTP
echo ptp_kvm > /etc/modules-load.d/ptp_kvm.conf
cat <<EOF > /etc/chrony/chrony.conf
log statistics measurements tracking
driftfile /var/lib/chrony/drift
makestep 1.0 3
maxupdateskew 100.0
dumpdir /var/lib/chrony
rtcfile /var/lib/chrony/rtc
rtcdevice /dev/ptp0
refclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0 stratum 2
EOF

# Install ssh keys
mkdir -p /home/virtu/.ssh/ /root/.ssh/
# Change the following line to use you ssh public key
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDb+9b1kDbeqeTrQ+lM6YlVdq6dVmw9beOLDh4r0yYrQs0I+mDA+c5q6PFCCiN6DVIjvP7YZdvFdT5w5E5eQc6hDLLLUMvWf8z9P/VHeyfnG3RCaVCKQImFelenO6fR+Wm4UtGd2Goi8Vend/wVW9n8b1E8FQqYCCGUsk8UT/TCrqjBhpfVVh9AdCgYuj8TyBAHVRN7LL+8MkwbNotzn26SlM1975heaQ0Mlmj7gSG3mUtAIGv0TkUZq9DJ0ClL6Xvldzlnupkk8JCsqSvbQXbPUNOWBEGZyJ7D/t+8lbxLWAWNVmsjuMOgyEJF+J1XD/9dwI3pABbptKAKMjsSrTywPCA1lXUqnkfKlINpoc1yjVEcZyXuWeTF9aRMF/WrAdQQSpHIo5mtGXwGZoHOvH2k+3kN/MexdyUiVjk5CLP+zIyI91STfmfx6Mns/xz7bLelsxVGT1nOu840l2y6KLYbOcfYN7dOuSXiFiMVsrpS8ltzhAcZPanvLJfdJsva2hE= virtu@ci-seapath' > /root/.ssh/authorized_keys
cp /root/.ssh/authorized_keys /home/virtu/.ssh/authorized_keys
chown -R root:root /root/.ssh/
chown -R virtu:virtu /home/virtu/.ssh
chmod 700 /root/.ssh/ /home/virtu/.ssh
chmod 600 /root/.ssh/authorized_keys /home/virtu/.ssh/authorized_keys

