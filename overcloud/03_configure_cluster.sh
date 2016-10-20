#!/bin/bash

# NOTE: this script is run only for first controller

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

function is_in_list() {
  value=$1
  list=$2
  for i in $(echo $list | sed 's/,/ /g') ; do
    if [[ $i == $value ]] ; then
      return 0
    fi
  done
  return 1
}

# NOTE: at this moment all nodes was installed and we can configure cluster
cloud_name=$(hostname | cut -d '-' -f 1)
controllers_internal_ips=`grep "${cloud_name}-controller-[0-9]\+-internalapi$" /etc/hosts | awk '{print($1)}' | tr '\r\n' ',' | sed 's/,$//g'`
export FACTER_mdm_ips="$controllers_internal_ips"

# Register protection domains and storage pools
protection_domains_array=($(echo ${ProtectionDomain:-''} | sed 's/,/ /g'))
storage_pools_list=${StoragePools:-''}
storage_pools_array=($(echo $storage_pools_list | sed 's/,/ /g'))
fault_sets_list='' # TODO: pass correct fault sets
for pd in ${protection_domains_array[@]} ; do
  pd_opts="sio_name=>'$pd'"
  if [[ -n "$storage_pools_list" ]] ; then
    sps="'$(echo $storage_pools_list | sed 's/,/'\'','\''/g')'"
    pd_opts+=", storage_pools=>[$sps]"
  fi
  if [[ -n "$fault_sets_list" ]] ; then
    fss="'$(echo $fault_sets_list | sed 's/,/'\'','\''/g')'"
    pd_opts+=", fault_sets=>[$fss]"
  fi
  cluster-cmd "scaleio::protection_domain { 'protection domain $pd': $pd_opts }"
  for sp in ${storage_pools_array[@]} ; do
    sp_opts="sio_name=>'$sp', protection_domain=>'$pd', checksum_mode=>"
    if [[ $ChecksumMode == "True" ]] ; then sp_opts+="'enable'"; else sp_opts+="'disable'"; fi
    sp_opts+=", scanner_mode=>"
    if [[ $ScannerMode == "True" ]] ; then sp_opts+="'enable'"; else sp_opts+="'disable'"; fi
    sp_opts+=", zero_padding_policy=>"
    if [[ $ZeroPadding == "True" ]] ; then sp_opts+="'enable'"; else sp_opts+="'disable'"; fi
    sp_opts+=", spare_percentage=>$SparePolicy"
    sp_opts+=", rfcache_usage=>"
    if is_in_list $sp "$RFCacheCachedPools" ; then sp_opts+="'use'"; else sp_opts+="'dont_use'"; fi
    sp_opts+=", rmcache_usage=>"
    if is_in_list $sp "$RMCacheCachedPools" ; then
      sp_opts+="'use', rmcache_write_handling_mode=>'cached'"
    elif is_in_list $sp "$RMCachePassthroughPools" ; then
      sp_opts+="'use', rmcache_write_handling_mode=>'passthrough'"
    else
      sp_opts+="'dont_use'"
    fi
    cluster-cmd "scaleio::storage_pool { 'storage pool $sp': $sp_opts }"
  done
done

# Register SDS nodes
# get somewhere a list of all nodes
# this hack is for Mitaka. for Newton we can get it from hiera (service_node_names)
device_paths_list=${DevicePaths:-''}
nodes=`grep -o "${cloud_name}-[a-zA-Z]\+-[0-9]\+\$" /etc/hosts`
for node in $nodes ; do
  role=$(echo $node | cut -d '-' -f 2)
  if [[ "$RolesForSDS" =~ "$role" ]] ; then
    sds_opts="sio_name=>'$node', protection_domain=>'$pd'"
    if [[ -n "$storage_pools_list" && -n "$device_paths_list" ]] ;then
      sds_opts+=", storage_pools=>'$storage_pools_list', device_paths=>'$device_paths_list'"
    fi
    if [[ -n "$RFCacheDevices" ]] ; then
      sds_opts+=", rfcache_devices=>'$RFCacheDevices'"
    fi
    node_storage_api_ip=$(awk "/${node}-storage\$/ {print(\$1)}" /etc/hosts)
    node_storagemgmt_api_ip=$(awk "/${node}-storagemgmt\$/ {print(\$1)}" /etc/hosts)
    if [[ "$node_storage_api_ip" != "$node_storagemgmt_api_ip" ]] ; then
      sds_opts+=", ips=>'$node_storage_api_ip,$node_storagemgmt_api_ip', ip_roles=>'sdc_only,sds_only'"
    else
      sds_opts+=", ips=>'$node_storage_api_ip', ip_roles=>'all'"
    fi
    cluster-cmd "scaleio::sds { '$node': $sds_opts }"
  fi
done
