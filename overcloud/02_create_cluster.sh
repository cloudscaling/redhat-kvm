#!/bin/bash

# NOTE: this script is run only for first controller

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

name="$(hostname)"
internal_ip=`python -c "import socket; print(sorted(socket.gethostbyname_ex('$name')[2])[0])"`

# NOTE: this code should be run only on master
# next code must be idempotent!!!
if ! scli --query_cluster --approve_certificate 2>/dev/null; then
  server-cmd "class { 'scaleio::mdm_server': master_mdm_name=>'$name', mdm_ips=>'$internal_ip', is_manager=>1 }"
  server-cmd "scaleio::login { 'first login': password=>'admin' }"
  server-cmd "scaleio::cluster { 'cluster': password=>'admin', new_password=>'$ScaleIOAdminPassword' }"
  # create client_user and set password for him
  # and set high performance profile for all
  cluster-cmd "scaleio::cluster { 'cluster': client_password=>'$ScaleIOClientPassword', performance_profile=>'high_performance' }"
fi

echo "INFO: step 02. node = $(hostname)" >> /var/log/scaleio.log
echo "Controllers count = $controllers_count" >> /var/log/scaleio.log
env | sort >> /var/log/scaleio.log

# NOTE: node replacement is not supported!!!
# TODO: calculate node roles from node list but not from node name only. here and in step 01.
slave_index=0
if (( controllers_count < 3 )) ; then
  mode=1
elif (( controllers_count < 5 )) ; then
  mode=3
  slave_index=2
else
  mode=5
  slave_index=3
fi

if (( mode > 1 )) ; then
  cloud_name=$(hostname | cut -d '-' -f 1)
  nodes=`grep -o "${cloud_name}-controller-[0-9]\+\$" /etc/hosts`
  for node in $nodes ; do
    # skip master
    if [[ "$(hostname)" == "$node" ]] ; then
      continue
    fi

    ip=`grep "${node}-internalapi$" /etc/hosts | awk '{print $1}'`
    node_index=$(echo "$node" | cut -d '-' -f 3)
    if (( node_index < slave_idex )) ; then
      role='manager'
    else
      role='tb'
    fi
    # TODO: pass management_ips to mdm
    cluster-cmd "scaleio::mdm { 'mdm $node': sio_name=>'$node', ips=>'$ip', role=>'$role' }"
  done
fi

cluster-cmd "scaleio::cluster { 'cluster': cluster_mode=>'$mode' }"


# TODO: add and provide options for cluster
# license-file-path, capacity-high-alert-threshold, capacity-critical-alert-threshold
