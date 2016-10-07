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

controllers_internal_ips=`grep "${cloud_name}-controller-[0-9]\+-internalapi$" /etc/hosts | awk '{print($1)}' | tr '\r\n' ',' | sed 's/,$//g'`

server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$controllers_internal_ips' }"

# TODO: run other steps accccording to $role
