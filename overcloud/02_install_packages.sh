#!/bin/bash

# Network mapping:
#   1. Internal API (OpenStack internal API, RPC, and DB):
#     - MDM/SDS/SDC <==> MDM
#     - Gateway <==> MDM
#     - SCLI <==> MDM
#   2. Storage (Access to storage resources from Compute and Controller nodes):
#     - SDS<==>SDC (data path)
#   3. Storage Management (Replication, Ceph back-end services)
#     - SDS<==>SDS (internal network for replication, etc)
#   4. Internal API VIP
#     - Nova/Cinder <==> Gateway (VIP)


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

  name="$(hostname)"
  cloud_name=$(hostname | cut -d '-' -f 1)
  node_suffix=$(hostname | cut -d '-' -f 3)
  # TODO: get index of node by $name from $names
  #names="$(hiera controller_node_names)"   # these variable are a comma separated list
  node_index="$node_suffix"
  internal_ip=$(awk "/${name}-internalapi$\$/ {print(\$1)}" /etc/hosts)
  controllers_count=$(grep -c "${cloud_name}-controller-[0-9]\+-internalapi$" /etc/hosts)
  #TODO: node replacement is not supported!!!
  first_controller_index=0
  if (( $controllers_count < 3 )) ; then
    mode=1_node
    managers_count=1
    tbs_count=0
  elif (( $controllers_count < 5 )) ; then
    mode=3_node
    managers_count=2
    tbs_count=1
  else
    mode=5_node
    managers_count=3
    tbs_count=2
  fi
  if (( $node_index - $first_controller_index < $managers_count )) ; then
    is_manager=1
  else
    is_manager=0
  fi

  server-cmd "class { 'scaleio::mdm_server': master_mdm_name=>'$name', mdm_ips=>'$internal_ip', is_manager=>$is_manager }"
  if [[ $node_index == $first_controller_index ]] ; then

    # next code must be idempotent!!!
    if ! scli --query_cluster --approve_certificate ; then
      server-cmd "scaleio::login { 'first login': password=>'admin' }"
      server-cmd "scaleio::cluster { 'cluster': password=>'admin', new_password=>'$ScaleIOAdminPassword' }"
      cluster-cmd "scaleio::cluster { 'cluster': client_password=>'$ScaleIOClientPassword' }"
    fi

    # TODO: add and provide options for cluster
    # license-file-path, capacity-high-alert-threshold, capacity-critical-alert-threshold

  else
    echo "Skip cluster confguration on non first controller"
  fi

  api_port=${GatewayPort:-4443}
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port' }"

  server-cmd "class { 'scaleio::gui_server': }"

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

fi

if [[ $RolesForSDS =~ $role ]] ; then
  server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"
fi
