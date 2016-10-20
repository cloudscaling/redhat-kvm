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
internal_ip=`grep "${name}-internalapi$" /etc/hosts | awk '{print($1)}'`

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

# register other MDMs
# puppet apply "scaleio::mdm { 'slave': sio_name=>'slave', ips=>'10.0.0.1', role=>'manager' }"
# puppet apply "scaleio::mdm { 'tb': sio_name=>'tb', ips=>'10.0.0.2', role=>'tb' }"


# TODO: add and provide options for cluster
# license-file-path, capacity-high-alert-threshold, capacity-critical-alert-threshold
