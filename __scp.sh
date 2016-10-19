#!/bin/bash -e

if [[ -z "$NUM" ]] ; then
  echo "Please set NUM variable to specific environment number. (export NUM=4)"
  exit 1
fi

BASE_ADDR=${BASE_ADDR:-172}
((addr=BASE_ADDR+NUM*10))

rm -f oc.tar
tar cvf oc.tar overcloud
scp -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null oc.tar root@192.168.$addr.2:/home/stack/oc.tar
rm -f oc.tar
scp -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null overcloud-install.sh root@192.168.$addr.2:/home/stack/overcloud-install.sh
