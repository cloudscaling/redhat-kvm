#!/bin/bash -e

source /etc/scaleio.env

DEST='/var/lib/scaleio/repo'
mkdir -p $DEST

packages=`curl --silent $PackagesSourceURL | grep -o 'EMC-ScaleIO-[_a-zA-Z0-9\.\-]*rpm' | sort | uniq`
for p in $packages ; do
  if [[ ! -f "$destination/$p" || ! -z "${FORCE_DOWNLOAD+x}" ]]
  then
    wget -P "$DEST/" "${PackagesSourceURL}${p}"
  fi
done

cat << EOF > /etc/yum.repos.d/scaleio.repo
[scaleio]
name=Local ScaleIO
baseurl=file://$DEST
gpgcheck=0
enabled=1
EOF

yum install -y createrepo
createrepo -v $DEST/
