#!/bin/bash -e

# common setting from create_env.sh
if [[ -z "$NUM" ]] ; then
  echo "Please set NUM variable to specific environment number. (export NUM=4)"
  exit 1
fi

SSH_VIRT_TYPE=${VIRT_TYPE:-'virsh'}
BASE_ADDR=${BASE_ADDR:-172}
MEMORY=${MEMORY:-8192}
SWAP=${SWAP:-0}
SSH_USER=${SSH_USER:-'stack'}


# su - stack

if [[ "$(whoami)" != "stack" ]] ; then
  echo "This script must be run under the 'stack' user"
  exit 1
fi

((addr=BASE_ADDR+NUM*10))
virt_host_ip="192.168.${addr}.1"
if [[ "$SSH_VIRT_TYPE" != 'vbox' ]] ; then
  virsh_opts="-c qemu+ssh://${SSH_USER}@${virt_host_ip}/system"
  list_vm_cmd="virsh $virsh_opts list --all"
else
  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  ssh_addr="${SSH_USER}@${virt_host_ip}"
  list_vm_cmd="ssh $ssh_opts $ssh_addr /usr/bin/VBoxManage list vms"
fi

CONTROLLER_COUNT=$($list_vm_cmd | grep rd-overcloud-$NUM-cont | wc -l)
COMPUTE_COUNT=$($list_vm_cmd | grep rd-overcloud-$NUM-comp | wc -l)
STORAGE_COUNT=$($list_vm_cmd | grep rd-overcloud-$NUM-stor | wc -l)
((OCM_COUNT=CONTROLLER_COUNT+COMPUTE_COUNT+STORAGE_COUNT))

# collect MAC addresses of overcloud machines
function get_macs() {
  type=$1
  count=$2
  truncate -s 0 /tmp/nodes-$type.txt
  for (( i=1; i<=count; i++ )) ; do
    if [[ "$SSH_VIRT_TYPE" != 'vbox' ]] ; then
      virsh $virsh_opts domiflist rd-overcloud-$NUM-$type-$i | awk '$3 ~ "prov" {print $5};'
    else
      ssh $ssh_opts $ssh_addr /usr/bin/VBoxManage showvminfo rd-overcloud-$NUM-$type-$i | awk '/NIC 1/ {print $4}' | cut -d ',' -f 1 | sed 's/\(..\)/\1:/g' | sed 's/:$//'
    fi
  done > /tmp/nodes-$type.txt
  echo "macs for '$type':"
  cat /tmp/nodes-$type.txt
}

get_macs cont $CONTROLLER_COUNT
get_macs comp $COMPUTE_COUNT
get_macs stor $STORAGE_COUNT

id_rsa=$(awk 1 ORS='\\n' ~/.ssh/id_rsa)
# create overcloud machines definition
cat << EOF > ~/instackenv.json
{
  "ssh-user": "$SSH_USER",
  "ssh-key": "$id_rsa",
  "host-ip": "$virt_host_ip",
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "arch": "x86_64",
  "nodes": [
EOF

function define_machine() {
  caps=$1
  mac=$2
  cat << EOF >> ~/instackenv.json
    {
      "pm_addr": "$virt_host_ip",
      "pm_user": "$SSH_USER",
      "pm_password": "$id_rsa",
      "pm_type": "pxe_ssh",
      "ssh_virt_type": "$SSH_VIRT_TYPE",
      "vbox_use_headless": "True",
      "mac": [
        "$mac"
      ],
      "cpu": "2",
      "memory": "$MEMORY",
      "disk": "30",
      "arch": "x86_64",
      "capabilities": "$caps"
    },
EOF
}

for (( i=1; i<=CONTROLLER_COUNT; i++ )) ; do
  mac=$(sed -n ${i}p /tmp/nodes-cont.txt)
  define_machine "profile:control,boot_option:local" $mac
done
for (( i=1; i<=COMPUTE_COUNT; i++ )) ; do
  mac=$(sed -n ${i}p /tmp/nodes-comp.txt)
  define_machine "profile:compute,boot_option:local" $mac
done
for (( i=1; i<=STORAGE_COUNT; i++ )) ; do
  mac=$(sed -n ${i}p /tmp/nodes-stor.txt)
  define_machine "profile:block-storage,boot_option:local" $mac
done

# remove last comma
head -n -1 ~/instackenv.json > ~/instackenv.json.tmp
mv ~/instackenv.json.tmp ~/instackenv.json
cat << EOF >> ~/instackenv.json
    }
  ]
}
EOF

# check this json (it's optional)
curl --silent -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
python instackenv-validator.py -f instackenv.json

source ./stackrc

# re-define flavors
for id in `openstack flavor list -f value -c ID` ; do openstack flavor delete $id ; done

swap_opts=''
if [[ $SWAP != 0 ]] ; then
  swap_opts="--swap $SWAP"
fi
openstack flavor create --id auto --ram $MEMORY $swap_opts --disk 28 --vcpus 2 baremetal
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" baremetal
openstack flavor create --id auto --ram $MEMORY $swap_opts --disk 28 --vcpus 2 control
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="control" control
openstack flavor create --id auto --ram $MEMORY $swap_opts --disk 28 --vcpus 2 compute
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="compute" compute
openstack flavor create --id auto --ram $MEMORY $swap_opts --disk 28 --vcpus 2 block-storage
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="block-storage" block-storage
openstack flavor list --long

# import overcloud configuration
openstack baremetal import --json instackenv.json
openstack baremetal list
# and configure overcloud
openstack baremetal configure boot

# do introspection - ironic will collect some hardware information from overcloud machines
openstack baremetal introspection bulk start
# this is a recommended command to check and wait end of introspection. but previous command can wait itself.
#sudo journalctl -l -u openstack-ironic-discoverd -u openstack-ironic-discoverd-dnsmasq -u openstack-ironic-conductor -f

tar xvf oc.tar
echo "Next step should be an overcloud deploy..."

# deploy overcloud. if you do it manually then I recommend to do it in screen.
echo "openstack overcloud deploy --templates --neutron-tunnel-types vxlan --neutron-network-type vxlan --ntp-server pool.ntp.org \
  --control-scale $CONTROLLER_COUNT --compute-scale $COMPUTE_COUNT --block-storage-scale $STORAGE_COUNT \
  --control-flavor control --compute-flavor compute --block-storage-flavor block-storage \
  -e overcloud/scaleio-env.yaml"
echo Add -e templates/firstboot/firstboot.yaml if you use swap


# check status of deployment. other heat commands also is useful to check status.
# heat resource-list -n 5 overcloud
