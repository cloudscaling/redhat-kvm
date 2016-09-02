#!/bin/bash -ex

# this script file should be copied to undercloud machine and run there.

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
useradd stack
echo "stack:password" | chpasswd
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack
su - stack

# install useful utils
sudo yum install -y yum-utils screen mc
# add OpenStack repositories
sudo curl -L -o /etc/yum.repos.d/delorean-mitaka.repo https://trunk.rdoproject.org/centos7-mitaka/current/delorean.repo
sudo curl -L -o /etc/yum.repos.d/delorean-deps-mitaka.repo http://trunk.rdoproject.org/centos7-mitaka/delorean-deps.repo
# install tripleo clients
sudo yum -y install yum-plugin-priorities python-tripleoclient python-rdomanager-oscplugin
# create undercloud configuration file. all IP addresses are relevant to create_env.sh script
cp /usr/share/instack-undercloud/undercloud.conf.sample ~/undercloud.conf
cat << EOF >> undercloud.conf
[DEFAULT]
local_ip = 192.168.176.1/24
undercloud_public_vip = 192.168.176.10
undercloud_admin_vip = 192.168.176.11
local_interface = eth1
masquerade_network = 192.168.176.0/24
dhcp_start = 192.168.176.100
dhcp_end = 192.168.176.120
network_cidr = 192.168.176.0/24
network_gateway = 192.168.176.1
discovery_iprange = 192.168.176.130,192.168.176.150
EOF

# install undercloud
openstack undercloud install

# function to build images if needed
function create_images() {
  mkdir -p ~/images
  cd ~/images
  export NODE_DIST=centos7
  export USE_DELOREAN_TRUNK=1
  export DELOREAN_REPO_FILE="delorean.repo"
  #export DELOREAN_TRUNK_REPO="http://buildlogs.centos.org/centos/7/cloud/x86_64/rdo-trunk-master-tripleo/"
  export DELOREAN_TRUNK_REPO="http://trunk.rdoproject.org/centos7-mitaka/current/"
  #export DIB_INSTALLTYPE_puppet_modules=source
  openstack overcloud image build --all
}

# but right now script will use previously built images
cd ~
tar xvf /tmp/images.tar

# upload images to undercloud
cd ~/images
source ../stackrc
openstack overcloud image upload
cd ..

# update undercloud's network information
sid=`neutron subnet-list | awk '/ 192.168.176.0/{print $2}'`
neutron subnet-update $sid --dns-nameserver 192.168.172.1

# increase timeouts due to virtual installation
sudo su -
openstack-config --set /etc/nova/nova.conf DEFAULT rpc_response_timeout 600
openstack-config --set /etc/ironic/ironic.conf DEFAULT rpc_response_timeout 600
openstack-service restart nova
openstack-service restart ironic
exit

# copy ssh key from undercloud machine to KVM host. it needs to allow control of host VM's from undercloud's ironic service
# TODO: this command needs to input password - rework it to batch mode
ssh -i ~/.ssh/id_rsa stack@192.168.172.1 "echo $(cat ~/.ssh/id_rsa.pub) > .ssh/authorized_keys ; chmod 600 .ssh/authorized_keys"
