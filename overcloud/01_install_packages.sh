#!/bin/bash -e

source /etc/scaleio.env

DEST='/var/lib/scaleio/repo'
mkdir -p $DEST

packages=`curl --silent $PackagesSourceURL | grep -o 'EMC-ScaleIO-[_a-zA-Z0-9\.\-]*rpm' | sort | uniq`
for p in $packages ; do
  if [[ ! -f "$DEST/$p" || ! -z "${FORCE_DOWNLOAD+x}" ]] ; then
    wget -P "$DEST/" "${PackagesSourceURL}${p}"
  fi
done

yum install -y createrepo
createrepo -v $DEST/

cat << EOF > /etc/yum.repos.d/scaleio.repo
[scaleio]
name=Local ScaleIO
baseurl=file://$DEST
gpgcheck=0
enabled=1
EOF


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

  cloud_name=$(hostname | cut -d '-' -f 1)
  controllers_count=$(grep -c "${cloud_name}-controller-[0-9]\+-internalapi$" /etc/hosts)
  if (( $controllers_count < 3 )) ; then
    managers_count=1
  elif (( $controllers_count < 5 )) ; then
    managers_count=2
  else
    managers_count=3
  fi
  #TODO: node replacement is not supported!!!
  first_controller_index=0
  node_index=$(hostname | cut -d '-' -f 3)
  if (( $node_index - $first_controller_index < $managers_count )) ; then
    is_manager=1
  else
    is_manager=0
  fi

  server-cmd "class { 'scaleio::mdm_server': is_manager=>$is_manager }"

  api_port=${GatewayPort:-4443}
  controllers_internal_ips=$(awk "/${cloud_name}-controller-[0-9]+-internalapi$/ {print(\$1)}" /etc/hosts | tr '\r\n' ',' | sed 's/,$//g')
  server-cmd "class { 'scaleio::gateway_server': port=>'$api_port', mdm_ips=>'$controllers_internal_ips' }"

  server-cmd "class { 'scaleio::gui_server': }"

elif [[ "$role" == "novacompute" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

elif [[ "$role" == "blockstorage" ]] ; then

  server-cmd "class { 'scaleio::sdc_server': ftp=>'$ScaleIODriverFTP' }"

fi

if [[ $RolesForSDS =~ $role ]] ; then
  server-cmd "class { 'scaleio::sds_server': ftp=>'$ScaleIODriverFTP' }"
fi
