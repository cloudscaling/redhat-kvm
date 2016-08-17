#!/bin/bash -ex

#on kvm host:
#1) create stack user, create home directory, add him to libvirtd group

while ! scp -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B /home/stack/images.tar root@192.168.172.2:/tmp/images.tar ; do echo "Waiting for undercloud..." ; sleep 30 ; done

ssh -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.172.2

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
hostnamectl set-hostname myhost.mydomain
hostnamectl set-hostname --transient myhost.mydomain
echo "127.0.0.1   localhost myhost myhost.mydomain" > /etc/hosts
systemctl restart network

yum update -y
useradd stack
echo "stack:password" | chpasswd
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack
su - stack


sudo yum install -y yum-utils screen
sudo curl -L -o /etc/yum.repos.d/delorean-mitaka.repo https://trunk.rdoproject.org/centos7-mitaka/current/delorean.repo
sudo curl -L -o /etc/yum.repos.d/delorean-deps-mitaka.repo http://trunk.rdoproject.org/centos7-mitaka/delorean-deps.repo
sudo yum -y install yum-plugin-priorities python-tripleoclient python-rdomanager-oscplugin
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

openstack undercloud install

# build images or copy existing

tar xvf /tmp/images.tar
cd images
source ../stackrc
openstack overcloud image upload
cd ..


sid=`neutron subnet-list | awk '/ 192.168.176.0/{print $2}'`
neutron subnet-update $sid --dns-nameserver 192.168.172.1

sudo su -
openstack-config --set /etc/nova/nova.conf DEFAULT rpc_response_timeout 600
openstack-config --set /etc/ironic/ironic.conf DEFAULT rpc_response_timeout 600
openstack-service restart nova
openstack-service restart ironic
exit

ssh -i ~/.ssh/id_rsa stack@192.168.172.1 "echo $(cat ~/.ssh/id_rsa.pub) > .ssh/authorized_keys ; chmod 600 .ssh/authorized_keys"
for i in {1..2} ; do virsh -c qemu+ssh://stack@192.168.172.1/system domiflist rd-overcloud-0-$i | awk '$3 ~ "prov" {print $5};' ; done > /tmp/nodes.txt
cat /tmp/nodes.txt


jq . << EOF > ~/instackenv.json
{
  "ssh-user": "stack",
  "ssh-key": "$(cat ~/.ssh/id_rsa)",
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "host-ip": "192.168.122.1",
  "arch": "x86_64",
  "nodes": [
    {
      "pm_addr": "192.168.172.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 1p /tmp/nodes.txt)"
      ],
      "cpu": "2",
      "memory": "4096",
      "disk": "30",
      "arch": "x86_64",
      "pm_user": "stack"
    },
    {
      "pm_addr": "192.168.172.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 2p /tmp/nodes.txt)"
      ],
      "cpu": "2",
      "memory": "4096",
      "disk": "30",
      "arch": "x86_64",
      "pm_user": "stack"
    }
  ]
}
EOF
curl -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
python instackenv-validator.py -f instackenv.json


source stackrc
openstack flavor delete baremetal || /bin/true
openstack flavor create --id auto --ram 4096 --disk 28 --vcpus 2 baremetal
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" baremetal

openstack baremetal import --json instackenv.json
openstack baremetal list
openstack baremetal configure boot

openstack baremetal introspection bulk start
#sudo journalctl -l -u openstack-ironic-discoverd -u openstack-ironic-discoverd-dnsmasq -u openstack-ironic-conductor -f

openstack overcloud deploy --templates --control-scale 1 --compute-scale 1 --neutron-tunnel-types vxlan --neutron-network-type vxlan

heat resource-list -n 5 overcloud



function create_images() {
  mkdir -p images
  cd images
  export NODE_DIST=centos7
  export USE_DELOREAN_TRUNK=1
  export DELOREAN_REPO_FILE="delorean.repo"
  #export DELOREAN_TRUNK_REPO="http://buildlogs.centos.org/centos/7/cloud/x86_64/rdo-trunk-master-tripleo/"
  export DELOREAN_TRUNK_REPO="http://trunk.rdoproject.org/centos7-mitaka/current/"
  #export DIB_INSTALLTYPE_puppet_modules=source
  openstack overcloud image build --all
}
