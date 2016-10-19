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

cloud_name=$(hostname | cut -d '-' -f 1)
controllers_internal_ips=`grep "${cloud_name}-controller-[0-9]\+-internalapi$" /etc/hosts | awk '{print($1)}' | tr '\r\n' ',' | sed 's/,$//g'`

# install SDC to all machines.
server-cmd "class { 'scaleio::sdc_server': mdm_ip=>'$controllers_internal_ips' }"

gateway_port=${GatewayPort:-4443}

if [[ "$role" == "controller" ]] ; then

  if [[ "$UseScaleioForGlance" == "True" ]] ; then
    echo "TODO: Implement glance support"
    # server-cmd "class { 'scaleio_openstack::glance': }"
  fi

elif [[ "$role" == "novacompute" ]] ; then

  # TODO: think about passing all protection domains instead of first
  server-cmd "class { 'scaleio_openstack::nova':
    gateway_user => 'scaleio_client', gateway_password => '$ScaleIOClientPassword',
    gateway_ip => '$public_vip', gateway_port => '$gateway_port',
    protection_domains => '$ProtectionDomain', storage_pools => '$StoragePools',
    provisioning_type => '$ProvisioningType',
  }"

elif [[ "$role" == "blockstorage" ]] ; then

  # TODO: think about passing all protection domains instead of first
  server-cmd "class { 'scaleio_openstack::cinder':
    gateway_user => 'scaleio_client', gateway_password => '$ScaleIOClientPassword',
    gateway_ip => '$public_vip', gateway_port => '$gateway_port',
    protection_domains => '$ProtectionDomain', storage_pools => '$StoragePools',
    provisioning_type => '$ProvisioningType',
  }"

fi
