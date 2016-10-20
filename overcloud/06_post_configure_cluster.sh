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

# apply high performance profile
# for SDC it can be done only after registring SDCs in MDM which done at step 05
cluster-cmd "scaleio::cluster { 'cluster': performance_profile=>'high_performance' }"
