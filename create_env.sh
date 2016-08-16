#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NUM=0
BASE_IMAGE="/var/lib/images/CentOS-7-x86_64-GenericCloud-1607.qcow2"

function get_network_name() {
  local type=$1
  case "$type" in
    management)
      echo "rd-mgmt-$NUM"
      ;;
    provisioning)
      echo "rd-prov-$NUM"
      ;;
    external)
      echo "rd-ext-$NUM"
      ;;
    *)
      return 1
  esac
}

function get_network_ip() {
  local type=$1
  case "$type" in
    management)
      ((addr=172+NUM*10))
      ;;
    provisioning)
      ((addr=176+NUM*10))
      ;;
    external)
      ((addr=175+NUM*10))
      ;;
    *)
      return 1
  esac
  echo "192.168.$addr"
}

function build_network_xml() {
  local type="$1"
  local nname="$2"
  local fname=`mktemp`
  local addr=$(get_network_ip $type)
  case "$type" in
    management)
      echo "<network><name>$nname</name><bridge name=\"$nname\" /><forward mode=\"nat\"/><ip address=\"$addr.1\" netmask=\"255.255.255.0\"/></network>" > $fname
      ;;
    provisioning)
      echo "<network><name>$nname</name><bridge name=\"$nname\" /><ip address=\"$addr.1\" netmask=\"255.255.255.0\"/></network>" > $fname
      ;;
    external)
      echo "<network><name>$nname</name><forward mode=\"nat\"><nat><port start=\"1024\" end=\"65535\"/></nat></forward><ip address=\"$addr.1\" netmask=\"255.255.255.0\"><dhcp><range start=\"$addr.2\" end=\"$addr.254\"/></dhcp></ip></network>" > $fname
      ;;
    *)
      return 1
  esac
  echo $fname
}

function create_network {
  local type="$1"
  local network_name=`get_network_name $type`
  virsh net-destroy $network_name 2> /dev/null || true
  virsh net-undefine $network_name 2> /dev/null || true
  local fxml=`build_network_xml $type $network_name`
  virsh net-define $fxml
  rm $fxml
  virsh net-autostart $network_name
  virsh net-start $network_name
}

function create_pool {
  local poolname="$1"
  local path="/var/lib/libvirt/$poolname"
  virsh pool-define-as $poolname dir - - - - "$path"
  virsh pool-build $poolname
  virsh pool-start $poolname
  virsh pool-autostart $poolname
}

function get_pool_path {
  local poolname=$1
  virsh pool-info $poolname &>/dev/null || return
  virsh pool-dumpxml $poolname | sed -n '/path/{s/.*<path>\(.*\)<\/path>.*/\1/;p}'
}

create_network management
mgmt_net=`get_network_name management`
create_network provisioning
prov_net=`get_network_name provisioning`
create_network external
ext_net=`get_network_name external`


for i in {1..2} ; do
  virsh destroy rd-overcloud-$NUM-$i || true
  sleep 2
  virsh undefine rd-overcloud-$NUM-$i || true
done
virsh destroy rd-undercloud-$NUM || true
sleep 2
virsh undefine rd-undercloud-$NUM || true

vm_disk_size="30G"
poolname="rdimages"
virsh pool-info $poolname &> /dev/null || create_pool $poolname
pool_path=$(get_pool_path $poolname)
for i in {1..2} ; do
  virsh vol-delete overcloud-$NUM-$i.qcow2 --pool $poolname || rm -f $pool_path/overcloud-$NUM-$i.qcow2
  qemu-img create -f qcow2 -o preallocation=metadata $pool_path/overcloud-$NUM-$i.qcow2 $vm_disk_size
done
cp $BASE_IMAGE $pool_path/undercloud-$NUM.qcow2
qemu-img resize $pool_path/undercloud-$NUM.qcow2 +32G

set -x

net_ip=$(get_network_ip "management")
net_mac="00:16:00:00:0$NUM:01"
rm -f kp kp.pub
ssh-keygen -b 2048 -t rsa -f "$my_dir/kp" -q -N ""
rootpass=`openssl passwd -1 123`

qemu-nbd -n -c /dev/nbd3 $pool_path/undercloud-$NUM.qcow2
sleep 5
tmpdir=$(mktemp -d)
mount /dev/nbd3p1 $tmpdir
sleep 2

cp "$my_dir/ifcfg-eth0" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i "s/{{network}}/$net_ip/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i "s/{{mac-address}}/$net_mac/g" $tmpdir/etc/sysconfig/network-scripts/ifcfg-eth0
mkdir -p $tmpdir/root/.ssh
cp "$my_dir/kp.pub" $tmpdir/root/.ssh/authorized_keys
echo "PS1='\${debian_chroot:+(\$debian_chroot)}undercloud:\[\033[01;31m\](\$?)\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\\$ '" >> $tmpdir/root/.bashrc
sed -i "s root:*: root:$rootpass: " $tmpdir/etc/shadow
grep root $tmpdir/etc/shadow
echo "PermitRootLogin yes" > $tmpdir/etc/ssh/sshd_config

umount /dev/nbd3p1
sleep 2
rm -rf $tmpdir
qemu-nbd -d /dev/nbd3
sleep 2

net_driver=${net_driver:-e1000}
virt-install --name=rd-undercloud-$NUM \
  --ram=5120 \
  --vcpus=1,cores=1 \
  --os-type=linux \
  --os-variant=rhel7 \
  --virt-type=kvm \
  --disk "path=$pool_path/undercloud-$NUM.qcow2",size=40,cache=writeback,bus=virtio,serial=$(uuidgen) \
  --boot hd \
  --noautoconsole \
  --network network=$mgmt_net,model=$net_driver,mac=$net_mac \
  --network network=$prov_net,model=$net_driver \
  --network network=$ext_net,model=$net_driver \
  --graphics vnc,listen=0.0.0.0

for i in {1..2} ; do
  virt-install --name rd-overcloud-$NUM-$i \
    --ram 4096 \
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
