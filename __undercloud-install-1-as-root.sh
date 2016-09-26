#!/bin/bash -e

# this script file should be copied to undercloud machine and run there.

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NETDEV=${NETDEV:-'eth1'}

# allow ip forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
# set static hostname
hostnamectl set-hostname myhost.mydomain
hostnamectl set-hostname --transient myhost.mydomain
echo "127.0.0.1   localhost myhost myhost.mydomain" > /etc/hosts
systemctl restart network

# update OS
yum update -y

# create stack user
if ! grep -q 'stack' /etc/passwd ; then 
  useradd stack
  echo "stack:password" | chpasswd
  echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
  chmod 0440 /etc/sudoers.d/stack
else
  echo User stack is already exist
fi

# install useful utils
yum install -y yum-utils screen mc
# add OpenStack repositories
curl -L -o /etc/yum.repos.d/delorean-mitaka.repo https://trunk.rdoproject.org/centos7-mitaka/current/delorean.repo
curl -L -o /etc/yum.repos.d/delorean-deps-mitaka.repo http://trunk.rdoproject.org/centos7-mitaka/delorean-deps.repo
# install tripleo clients
yum -y install yum-plugin-priorities python-tripleoclient python-rdomanager-oscplugin sshpass openstack-utils

# another hack to avoid 'sudo: require tty' error
#sed -i -e 's/Defaults    requiretty.*/ #Defaults    requiretty/g' /etc/sudoers

cp "$my_dir/__undercloud-install-2-as-stack-user.sh" /home/stack/
chown stack /home/stack/__undercloud-install-2-as-stack-user.sh
sudo -u stack NUM=$NUM NETDEV=$NETDEV /home/stack/__undercloud-install-2-as-stack-user.sh

# increase timeouts due to virtual installation
openstack-config --set /etc/nova/nova.conf DEFAULT rpc_response_timeout 600
openstack-config --set /etc/ironic/ironic.conf DEFAULT rpc_response_timeout 600
openstack-service restart nova
openstack-service restart ironic
