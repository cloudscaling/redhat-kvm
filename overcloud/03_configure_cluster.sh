#!/bin/bash

source /etc/scaleio.env

function server-cmd() {
  puppet apply -e "$1" --detailed-exitcodes
  local exit_code=$?
  if [[ $exit_code != 0 && $exit_code != 2 ]]; then
    echo "The run failed. Exit code is $exit_code."
    exit 1
  fi
}

function cluster-cmd() {
    server-cmd "scaleio::login {'login': password=>'$ScaleIOAdminPassword'} -> $1"
}

# these variable are a comma separated list
ips="$(hiera controller_node_ips)"
names="$(hiera controller_node_names)"

name="$(hostname)"

local_ip=`python -c "import socket; print(sorted(socket.gethostbyname_ex('$name')[2])[0])"`

protection_domains_array=($(echo ${ProtectionDomain:-'pd'} | sed 's/,/ /g'))
storage_pools_list=${StoragePools:-'sp1'}
storage_pools_array=($(echo $storage_pools_list | sed 's/,/ /g'))


# TODO: pass correct fault sets
fault_sets_list='fs'

role=$(hostname | cut -d '-' -f 2)
if [[ "$role" == "controller" ]] ; then

  node_suffix=$(hostname | cut -d '-' -f 3)
  # TODO: get index of node by suffix from $names
  node_index="$node_suffix"
  if [[ $node_index == 0 ]] ; then
    # NOTE: at this moment all nodes was installed and we can configure cluster

    server-cmd "class { 'scaleio::gateway_server': mdm_ips=>'$ips' }"

    # TODO: investigate networks definitions
    export FACTER_mdm_ips="$ips"
    # TODO: add standby mdms if needed
    #cluster-cmd "scaleio::mdm { 'mdm $node': sio_name=>'$name', ips=>'$internal_ip', role=>'$role', management_ips=>$management_ip }"

    # get somewhere a list of all nodes
    # this hack is for Mitaka. for Newton we can get it from hiera (service_node_names)
    cloud_name=$(hostname | cut -d '-' -f 1)
    nodes=`grep -o "${cloud_name}-[a-zA-Z]*-[0-9]\$" /etc/hosts`
    for node in $nodes ; do
      role=$(echo $node | cut -d '-' -f 2)
      if [[ $RolesForSDS =~ $role ]] ; then
        for pd in ${protection_domains_array[@]} ; do
          cluster-cmd "scaleio::protection_domain { 'protection domain $pd': sio_name=>'$pd', fault_sets=>[$fault_sets_list], storage_pools=>[$storage_pools_list] }"
          for sp in ${storage_pools_array[@]} ; do
            # TODO: define and pass storage pool options
            cluster-cmd "scaleio::storage_pool { 'storage pool $sp': sio_name=>'$sp', protection_domain=>'$pd' }"
          done
        done

        ip=`python -c "import socket; print(sorted(socket.gethostbyname_ex('$node')[2])[0])"`
        # TODO: define and pass SDS options
        cluster-cmd "scaleio::sds { '$node': sio_name=>'$node', ips=>'$ip', ip_roles=>'all', protection_domain=>'$pd', storage_pools=>'$sps', device_paths=>'$DevicePaths' }"
      fi
    done
  fi

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$ips' }"

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$ips' }"

fi
