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

role=$(hostname | cut -d '-' -f 2)
if [[ "$role" == "controller" ]] ; then

  # these variable are a comma separated list
  ips="$(hiera controller_node_ips)"
  names="$(hiera controller_node_names)"

  name="$(hostname)"
  # TODO: investigate networks definitions
  internal_ip="$ips"
  management_ip="$ips"

  node_suffix=$(hostname | cut -d '-' -f 3)
  # TODO: get index of node by $name from $names
  node_index="$node_suffix"
  if [[ $node_index == 0 ]] ; then

    # next code must be idempotent!!!
    if ! scli --query_cluster --approve_certificate ; then
      server-cmd "class { 'scaleio::mdm_server': master_mdm_name=>'$name', mdm_ips=>'$internal_ip', is_manager=>1, mdm_management_ips=>'$management_ip' }"
      server-cmd "scaleio::login { 'first login': password=>'admin' }"
      server-cmd "scaleio::cluster { 'cluster': password=>'admin', new_password=>'$ScaleIOAdminPassword' }"
      cluster-cmd "scaleio::cluster { 'cluster': client_password=>'$ScaleIOClientPassword' }"
    fi

    # TODO: add and provide options for cluster
    # license-file-path, capacity-high-alert-threshold, capacity-critical-alert-threshold

  else
    # TODO: register other managers and tie-breakers (is_manager = 1 or 0)
    # server-cmd "class { 'scaleio::mdm_server': is_manager=>$is_manager }"
    echo "more than one controller is not supported"
    exit 1
  fi
fi
