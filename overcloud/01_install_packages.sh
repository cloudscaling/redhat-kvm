#!/bin/bash -e

source /etc/scaleio.env

# install packages needed for deployment
yum install -y wget git

# install puppets for ScaleIO deployment
if [[ "$PuppetsVersion" == "master" ]] ; then
  # last version from github
  for dep in puppetlabs-firewall puppetlabs-stdlib puppetlabs-inifile ; do
    puppet module install $dep || /bin/true
  done
  rm -rf /etc/puppet/modules/scaleio
  git clone -q https://github.com/emccode/puppet-scaleio /etc/puppet/modules/scaleio
  rm -rf /etc/puppet/modules/scaleio_openstack
  git clone -q https://github.com/emccode/puppet-scaleio-openstack /etc/puppet/modules/scaleio_openstack
else
  # or stable version from puppet forge
  # NOTE: this module can't be installed due to strange installed modules
  # script fixes pacemaker's metadata to avoid bug at installation
  sed -i 's/>\~1\.7\.0/>=1.7.0/g' /etc/puppet/modules/pacemaker/metadata.json
  # do not fail script - modules can be already present
  puppet module install --version "$PuppetsVersion" cloudscaling-scaleio || /bin/true
  puppet module install --version "$PuppetsVersion" cloudscaling-scaleio_openstack || /bin/true
fi

function server-cmd() {
  set +e
  puppet apply -e "$1" --detailed-exitcodes
  local exit_code=$?
  set -e
  if [[ $exit_code != 0 && $exit_code != 2 ]]; then
    echo "The run failed. Exit code is $exit_code."
    exit 1
  fi
}

if [[ "$role" == "controller" ]] ; then
  echo "Step 01. Role is '$role'"

  # calculate count of MDM's and current node role
  cloud_name=$(hostname | cut -d '-' -f 1)
  controllers_count=$(grep -c "${cloud_name}-controller-[0-9]\+[-\.]internalapi$" /etc/hosts)
  if (( controllers_count < 3 )) ; then
    managers_count=1
  elif (( controllers_count < 5 )) ; then
    managers_count=2
  else
    managers_count=3
  fi
  # NOTE: node replacement is not supported!!!
  first_controller_index=0
  node_index=$(hostname | cut -d '-' -f 3)
  if (( node_index - first_controller_index < managers_count )) ; then
    is_manager=1
  else
    is_manager=0
  fi

  # install MDM
  server-cmd "class { 'scaleio::mdm_server': is_manager=>$is_manager, pkg_ftp=>'$PackagesSourceURL' }"

  # install Gateway
  api_port=${GatewayPort:-4443}
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port', pkg_ftp=>'$PackagesSourceURL' }"

  # install GUI
  server-cmd "class { 'scaleio::gui_server': pkg_ftp=>'$PackagesSourceURL'}"

elif [[ "$role" == "novacompute" ]] ; then
  echo "Step 01. Role is '$role'"

elif [[ "$role" == "blockstorage" ]] ; then
  echo "Step 01. Role is '$role'"

fi

# step 05 calls sdc_server for all to set MDM ips. so it must be installed for all.
server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP', pkg_ftp=>'$PackagesSourceURL' }"

if [[ "$RolesForSDS" =~ "$role" ]] ; then
  # install SDS
  server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP', pkg_ftp=>'$PackagesSourceURL' }"
fi
