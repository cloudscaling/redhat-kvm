#!/bin/bash

puppet module install --version "<1.2.0" cloudscaling-scaleio
puppet module install --version "<1.2.0" cloudscaling-scaleio_openstack

role=$(hostname | cut -d '-' -f 2)

if [[ "$role" == "controller" ]] ; then

  server-cmd "class { 'scaleio::mdm_server': }"

  # TODO: support haproxy for gateway
  api_port=$GatewayPort
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port' }"

  server-cmd "class { 'scaleio::gui_server': }"

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

  if [[ $InstallSDSToCompute == 'true' ]] ; then
    server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"
  fi

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"
  server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"

fi
