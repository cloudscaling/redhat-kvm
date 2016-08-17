#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NUM=0
BASE_IMAGE="/var/lib/images/CentOS-7-x86_64-GenericCloud-1607.qcow2"
vm_disk_size="30G"
poolname="rdimages"

source "$my_dir/functions"

delete_domains

create_network management
mgmt_net=`get_network_name management`
create_network provisioning
prov_net=`get_network_name provisioning`
create_network external
ext_net=`get_network_name external`

virsh pool-info $poolname &> /dev/null || create_pool $poolname
pool_path=$(get_pool_path $poolname)
for i in {1..2} ; do
  virsh vol-delete overcloud-$NUM-$i.qcow2 --pool $poolname || rm -f $pool_path/overcloud-$NUM-$i.qcow2
  qemu-img create -f qcow2 -o preallocation=metadata $pool_path/overcloud-$NUM-$i.qcow2 $vm_disk_size
done
cp $BASE_IMAGE $pool_path/undercloud-$NUM.qcow2
qemu-img resize $pool_path/undercloud-$NUM.qcow2 +32G

mgmt_ip=$(get_network_ip "management")
mgmt_mac="00:16:00:00:0$NUM:02"
prov_ip=$(get_network_ip "provisioning")
prov_mac="00:16:00:00:0$NUM:06"
rm -f kp kp.pub
ssh-keygen -b 2048 -t rsa -f "$my_dir/kp" -q -N ""
rootpass=`openssl passwd -1 123`

qemu-nbd -n -c /dev/nbd3 $pool_path/undercloud-$NUM.qcow2
sleep 5
tmpdir=$(mktemp -d)
mount /dev/nbd3p1 $tmpdir
sleep 2

# configure eth0 - management
cp "$my_dir/ifcfg-ethM" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i "s/{{network}}/$mgmt_ip/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i "s/{{mac-address}}/$mgmt_mac/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
# configure eth1 - provisioning
cp "$my_dir/ifcfg-ethA" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth1
sed -i "s/{{network}}/$prov_ip/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth1
sed -i "s/{{mac-address}}/$prov_mac/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth1
# configure root access
mkdir -p $tmpdir/root/.ssh
cp "$my_dir/kp.pub" $tmpdir/root/.ssh/authorized_keys
echo "PS1='\${debian_chroot:+(\$debian_chroot)}undercloud:\[\033[01;31m\](\$?)\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\\$ '" >> $tmpdir/root/.bashrc
sed -i "s root:\*: root:$rootpass: " $tmpdir/etc/shadow
sed -i "s root:\!\!: root:$rootpass: " $tmpdir/etc/shadow
grep root $tmpdir/etc/shadow
echo "PermitRootLogin yes" > $tmpdir/etc/ssh/sshd_config

umount /dev/nbd3p1
sleep 2
rm -rf $tmpdir
qemu-nbd -d /dev/nbd3
sleep 2

net_driver=${net_driver:-e1000}
virt-install --name=rd-undercloud-$NUM \
  --ram=6144 \
  --vcpus=1,cores=1 \
  --os-type=linux \
  --os-variant=rhel7 \
  --virt-type=kvm \
  --disk "path=$pool_path/undercloud-$NUM.qcow2",size=40,cache=writeback,bus=virtio,serial=$(uuidgen) \
  --boot hd \
  --noautoconsole \
  --network network=$mgmt_net,model=$net_driver,mac=$mgmt_mac \
  --network network=$prov_net,model=$net_driver,mac=$prov_mac \
  --network network=$ext_net,model=$net_driver \
  --graphics vnc,listen=0.0.0.0

for i in {1..2} ; do
  virt-install --name rd-overcloud-$NUM-$i \
    --ram 8192 \
    --vcpus 2 \
    --os-variant rhel7 \
    --disk "path=$pool_path/overcloud-$NUM-$i.qcow2,device=disk,bus=virtio,format=qcow2" \
    --noautoconsole \
    --vnc \
    --network network=$prov_net,model=$net_driver \
    --network network=$ext_net,model=$net_driver \
    --cpu SandyBridge,+vmx \
    --dry-run --print-xml > /tmp/oc-$NUM-$i.xml
  virsh define --file /tmp/oc-$NUM-$i.xml
done
