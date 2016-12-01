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

api_port=${GatewayPort:-4443}
cloud_name=$(hostname | cut -d '-' -f 1)
controllers_internal_ips=`grep "${cloud_name}-controller-[0-9]\+[-\.]internalapi$" /etc/hosts | awk '{print($1)}' | tr '\r\n' ',' | sed 's/,$//g'`
use_load_balancer=`hiera enable_load_balancer`

# Configure Gateway HA
if [[ -n "$public_vip" && "$use_load_balancer" == "true" ]] ; then
  (( int_api_port=api_port-1 ))
  controllers_names="$(hiera controller_node_names)"
  server_names="'$(echo $controllers_names | sed 's/,/'\'','\''/g')'"
  ipaddresses="'$(echo $controllers_internal_ips | sed 's/,/'\'','\''/g')'"
  #TODO: tmp hack, we should not call tripleo::loadbalancer.
  # Ideally it should be in the .yaml & tripleo puppet lib
  cmd="\
    class { 'scaleio::gateway_server': \
      port=>'$int_api_port', \
      mdm_ips=>'$controllers_internal_ips' \
    } -> \
    haproxy::listen { 'scaleio-gateway': \
      bind => { '${public_vip}:${api_port}' => [], }, \
      options => { 'balance' => 'roundrobin', 'mode' => 'tcp', 'option' => ['tcplog'], }, \
      collect_exported => false, \
    } -> \
    haproxy::balancermember { 'scaleio-gateway': \
      listening_service => 'scaleio-gateway', \
      ports => ${int_api_port}, \
      ipaddresses => [${ipaddresses}], \
      server_names => [${server_names}], \
      options => 'backup check inter 10s fastinter 2s downinter 3s rise 3 fall 3', \
    } -> \
    class { '::tripleo::loadbalancer' : \
      controller_hosts       => [${ipaddresses}], \
      controller_hosts_names => [${server_names}], \
      manage_vip             => false, \
      mysql_clustercheck     => true, \
      haproxy_service_manage => false, \
    } ~> \
    service { 'haproxy': \
      ensure => 'running', \
    }  \
  "
  server-cmd "$cmd"
  
else
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port', mdm_ips=>'$controllers_internal_ips' }"
fi

