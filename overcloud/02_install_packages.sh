#!/bin/bash

source /etc/scaleio.env

if [[ "$UsePuppetsFromUpstream" == "True" ]] ; then
  for dep in puppetlabs-firewall puppetlabs-stdlib puppetlabs-inifile ; do
    puppet module install $dep || /bin/true
  done
  rm -rf /etc/puppet/modules/scaleio
  git clone -q https://github.com/emccode/puppet-scaleio /etc/puppet/modules/scaleio
  rm -rf /etc/puppet/modules/scaleio_openstack
  git clone -q https://github.com/emccode/puppet-scaleio-openstack /etc/puppet/modules/scaleio_openstack
else
  puppet module install --version "<1.2.0" cloudscaling-scaleio_openstack
  # NOTE: this module can't be installed due to strange installed modules
  # TODO: fix it...
  puppet module install --version "<1.2.0" cloudscaling-scaleio
fi

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
    if ! scli --query_cluster ; then
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

  # TODO: support haproxy for gateway
  api_port=$GatewayPort
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port' }"

  server-cmd "class { 'scaleio::gui_server': }"

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

  if [[ $InstallSDSToCompute == 'True' ]] ; then
    server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"
  fi

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"
  server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"

fi
