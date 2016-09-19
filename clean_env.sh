#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NUM=${NUM:-0}
poolname="rdimages"

source "$my_dir/functions"

delete_network management
delete_network provisioning
delete_network external

delete_domains

# TODO: calculate real count of existing volumes
for (( i=1; i<=10; i++ )) ; do
  delete_volume overcloud-$NUM-cont-$i.qcow2 $poolname
  delete_volume overcloud-$NUM-comp-$i.qcow2 $poolname
  delete_volume overcloud-$NUM-stor-$i.qcow2 $poolname
  delete_volume overcloud-$NUM-stor-$i-store.qcow2 $poolname
done
