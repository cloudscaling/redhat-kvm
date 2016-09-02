#!/bin/bash -ex

# ssh keys are in place - collect MAC addresses of overcloud machines
for i in {1..2} ; do virsh -c qemu+ssh://stack@192.168.172.1/system domiflist rd-overcloud-0-$i | awk '$3 ~ "prov" {print $5};' ; done > /tmp/nodes.txt
cat /tmp/nodes.txt

# create overcloud machines definition
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
# check this json (it's optional)
curl -O https://raw.githubusercontent.com/rthallisey/clapper/master/instackenv-validator.py
python instackenv-validator.py -f instackenv.json

# re-define baremetal flavor
openstack flavor delete baremetal || /bin/true
openstack flavor create --id auto --ram 8192 --disk 28 --vcpus 2 baremetal
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" baremetal

# import overcloud configuration
openstack baremetal import --json instackenv.json
openstack baremetal list
# and configure overcloud
openstack baremetal configure boot

# do introspection - ironic will collect some hardware information from overcloud machines
openstack baremetal introspection bulk start
# this is a recommended command to check and wait end of introspection. but previous command can wait itself.
#sudo journalctl -l -u openstack-ironic-discoverd -u openstack-ironic-discoverd-dnsmasq -u openstack-ironic-conductor -f

# deploy overcloud. if you do it manually then I recommend to do it in screen.
openstack overcloud deploy --templates --control-scale 1 --compute-scale 1 --neutron-tunnel-types vxlan --neutron-network-type vxlan

# check status of deployment. other heat commands also is useful to check status.
heat resource-list -n 5 overcloud
