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
controllers_internal_ips=`grep "${cloud_name}-controller-[0-9]+-internalapi$" /etc/hosts | awk '{print($1)}' | tr '\r\n' ',' | sed 's/,$//g'`

api_port=${GatewayPort:-4443}
server-cmd "class { 'scaleio::gateway_server': port=>'$api_port', mdm_ips=>'$controllers_internal_ips' }"

# Configure Gateway HA
gateway_vip=$(hiera 'tripleo::loadbalancer::internal_api_virtual_ip')
if [[ "$gateway_vip" != 'nil' ]] ; then
  listen_opts="bind => { '${gateway_vip}:${api_port}' => [], }"
  listen_opts+=", options => { 'balance' => 'roundrobin', 'mode' => 'tcp', 'option' => ['tcplog'], }"
  listen_opts+=", collect_exported => false"
  server-cmd "haproxy::listen { 'scaleio-gateway': ${listen_opts} }"
  balance_opts="listening_service => 'scaleio-gateway'"
  balance_opts+=", ports => '${api_port}'"
  ipaddresses="'$(echo $controllers_internal_ips | sed 's/,/'\'','\''/g')'"
  balance_opts+=", ipaddresses => [$ipaddresses]"
  controllers_names="$(hiera controller_node_names)"
  server_names="'$(echo $controllers_names | sed 's/,/'\'','\''/g')'"
  balance_opts+=", server_names => [$server_names]"
  balance_opts+=", options => 'check inter 10s fastinter 2s downinter 3s rise 3 fall 3'"
  server-cmd "haproxy::balancermember { 'scaleio-gateway': ${balance_opts} }"
fi