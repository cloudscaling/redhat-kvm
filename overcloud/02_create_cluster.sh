#!/bin/bash

# NOTE: this script is run only for first controller
# TODO: rework script runner for registering other managers and tie-breakers (is_manager = 1 or 0)
# server-cmd "class { 'scaleio::mdm_server': is_manager=>$is_manager }"

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
internal_ip=`grep "${name}-internalapi$" /etc/hosts | awk '{print($1)}'`

# next code must be idempotent!!!
if ! scli --query_cluster --approve_certificate ; then
  server-cmd "class { 'scaleio::mdm_server': master_mdm_name=>'$name', mdm_ips=>'$internal_ip', is_manager=>1 }"
  server-cmd "scaleio::login { 'first login': password=>'admin' }"
  server-cmd "scaleio::cluster { 'cluster': password=>'admin', new_password=>'$ScaleIOAdminPassword' }"
  cluster-cmd "scaleio::cluster { 'cluster': client_password=>'$ScaleIOClientPassword' }"
fi

# TODO: add and provide options for cluster
# license-file-path, capacity-high-alert-threshold, capacity-critical-alert-threshold


