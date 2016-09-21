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
    server-cmd "scaleio::login {'login': password=>'$AdminPassword'} -> $1"
}

# TODO: check format of these variables for more than one controller
ips="$(hiera controller_node_ips)"
names="$(hiera controller_node_names)"

name="$(hostname)"

local_ip=`python -c "import socket; print(sorted(socket.gethostbyname_ex('$name')[2])[0])"`

# TODO: pass correct protection domain name and storage pools
pd='pd'
sps='sp1'

role=$(hostname | cut -d '-' -f 2)
if [[ "$role" == "controller" ]] ; then

  node_suffix=$(hostname | cut -d '-' -f 3)
  # TODO: get index of node by suffix from $names
  node_index="$node_suffix"
  if [[ $node_index == 0 ]] ; then
    # NOTE: at this moment all nodes was installed and we can configure cluster

    # TODO: investigate networks definitions
    export FACTER_mdm_ips='$ips'

    # TODO: add stndby mdms if needed
    #cluster-cmd "scaleio::mdm { 'mdm $node': sio_name=>'$name', ips=>'$internal_ip', role=>'$role', management_ips=>$management_ip }"

    server-cmd "class { 'scaleio::gateway_server': mdm_ips=>'$ips' }"
  fi

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$ips' }"

  if [[ $InstallSDSToCompute == 'True' ]] ; then
    server-cmd "scaleio::sds { '$name': sio_name=>'$name', ips=>'$local_ip', ip_roles=>'all', protection_domain=>'$pd', storage_pools=>'$sps', device_paths=>'$DevicePaths' }"
  fi

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$ips' }"
  server-cmd "scaleio::sds { '$name': sio_name=>'$name', ips=>'$local_ip', ip_roles=>'all', protection_domain=>'$pd', storage_pools=>'$sps', device_paths=>'$DevicePaths' }"

fi
