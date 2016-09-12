#!/bin/bash -ex

# su - stack

# ssh keys are in place - collect MAC addresses of overcloud machines
for i in {1..5} ; do virsh -c qemu+ssh://stack@192.168.172.1/system domiflist rd-overcloud-0-$i | awk '$3 ~ "prov" {print $5};' ; done > /tmp/nodes.txt
cat /tmp/nodes.txt

id_rsa=$(awk 1 ORS='\\n' ~/.ssh/id_rsa)
# create overcloud machines definition
cat << EOF > ~/instackenv.json
{
  "ssh-user": "stack",
  "ssh-key": "$id_rsa",
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "host-ip": "192.168.122.1",
  "arch": "x86_64",
  "nodes": [
EOF

for i in {1..5} ; do
  if (( i == 1 )) ; then
    caps="profile:control,boot_option:local"
  elif (( i == 2 )) ; then
    caps="profile:compute,boot_option:local"
  else
    caps="profile:block-storage,boot_option:local"
  fi
  cat << EOF >> ~/instackenv.json
    {
      "pm_addr": "192.168.172.1",
      "pm_password": "$id_rsa",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n ${i}p /tmp/nodes.txt)"
      ],
      "cpu": "2",
      "memory": "8192",
      "disk": "30",
      "arch": "x86_64",
      "pm_user": "stack",
      "capabilities": "$caps"
EOF
  if (( i != 5 )) ; then
    echo "    }," >> ~/instackenv.json
  else
    echo "    }" >> ~/instackenv.json
  fi
done
cat << EOF >> ~/instackenv.json
  ]
}
EOF
# check this json (it's optional)
curl -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
python instackenv-validator.py -f instackenv.json

source ./stackrc

# re-define flavors
for id in `openstack flavor list -f value -c ID` ; do openstack flavor delete $id ; done

openstack flavor create --id auto --ram 8192 --disk 28 --vcpus 2 baremetal
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" baremetal
openstack flavor create --id auto --ram 8192 --disk 28 --vcpus 2 control
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="control" control
openstack flavor create --id auto --ram 8192 --disk 28 --vcpus 2 compute
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="compute" compute
openstack flavor create --id auto --ram 8192 --disk 28 --vcpus 2 block-storage
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

echo "Next step should be an overcloud deploy..."
exit 0

# deploy overcloud. if you do it manually then I recommend to do it in screen.
openstack overcloud deploy --templates --control-scale 1 --compute-scale 1 --neutron-tunnel-types vxlan --neutron-network-type vxlan --block-storage-scale 3 -e overcloud/scaleio-env.yaml

# check status of deployment. other heat commands also is useful to check status.
heat resource-list -n 5 overcloud
