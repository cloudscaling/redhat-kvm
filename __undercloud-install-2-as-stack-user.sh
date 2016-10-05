#!/bin/bash -ex

# this script file should be copied to undercloud machine and run there.

cd ~

NETDEV=${NETDEV:-'eth1'}
SKIP_SSH_TO_HOST_KEY=${SKIP_SSH_TO_HOST_KEY:-'no'}
((addr=176+NUM*10))
prov_ip="192.168.$addr"
((addr=172+NUM*10))
mgmt_ip="192.168.$addr"
dns_nameserver="8.8.8.8"

# create undercloud configuration file. all IP addresses are relevant to create_env.sh script
cp /usr/share/instack-undercloud/undercloud.conf.sample ~/undercloud.conf
cat << EOF >> undercloud.conf
[DEFAULT]
local_ip = $prov_ip.2/24
undercloud_public_vip = $prov_ip.10
undercloud_admin_vip = $prov_ip.11
local_interface = $NETDEV
masquerade_network = $prov_ip.0/24
dhcp_start = $prov_ip.100
dhcp_end = $prov_ip.120
network_cidr = $prov_ip.0/24
network_gateway = $prov_ip.2
discovery_iprange = $prov_ip.130,$prov_ip.150
EOF

# install undercloud
openstack undercloud install

# function to build images if needed
function create_images() {
  mkdir -p ~/images
  cd ~/images

  # next line is needed only if undercloud's OS is deifferent
  #export NODE_DIST=centos7
  export STABLE_RELEASE=mitaka
  export USE_DELOREAN_TRUNK=1
  export DELOREAN_REPO_FILE="delorean.repo"
  export DELOREAN_TRUNK_REPO="http://trunk.rdoproject.org/centos7-mitaka/current/"
  export DIB_YUM_REPO_CONF=/etc/yum.repos.d/delorean*

  #export DELOREAN_TRUNK_REPO="http://buildlogs.centos.org/centos/7/cloud/x86_64/rdo-trunk-master-tripleo/"
  #export DIB_INSTALLTYPE_puppet_modules=source

  openstack overcloud image build --all
}

# but right now script will use previously built images
cd ~
tar xvf /tmp/images.tar

# upload images to undercloud
source ./stackrc
cd ~/images
openstack overcloud image upload
cd ..

# update undercloud's network information
sid=`neutron subnet-list | grep " $prov_ip.0" | awk '{print $2}'`
neutron subnet-update $sid --dns-nameserver $dns_nameserver

mkdir -p .ssh
cat <<EOF >.ssh/config
Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
EOF
chmod 644 .ssh/config

# copy ssh key from undercloud machine to KVM host. it needs to allow control of host VM's from undercloud's ironic service
# TODO: this command needs to input password - rework it to batch mode
if [[ "$SKIP_SSH_TO_HOST_KEY" != "yes" ]] ; then
  sshpass -p password ssh -i ~/.ssh/id_rsa stack@${mgmt_ip}.1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "echo $(cat ~/.ssh/id_rsa.pub) >> .ssh/authorized_keys ; chmod 600 .ssh/authorized_keys"
fi
