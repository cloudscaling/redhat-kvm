#!/bin/bash -e

# NOTE: installs Mitaka version

# common setting from create_env.sh
if [[ -z "$NUM" ]] ; then
  echo "Please set NUM variable to specific environment number. (export NUM=4)"
  exit 1
fi

BASE_ADDR=${BASE_ADDR:-172}
IMAGES=${IMAGES:-'/home/stack/images.tar'}
NETDEV=${NETDEV:-'eth1'}
SKIP_SSH_TO_HOST_KEY=${SKIP_SSH_TO_HOST_KEY:-'no'}

# on kvm host do once: create stack user, create home directory, add him to libvirtd group
((env_addr=BASE_ADDR+NUM*10))
ip_addr="192.168.${env_addr}.2"
ssh_opts="-i $my_dir/kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_addr="root@${ip_addr}"

# wait for undercloud and copy images for overcloud to it. (images can be build manually but it's too long - use previously built images)
while ! scp $ssh_opts -B $IMAGES ${ssh_addr}:/tmp/images.tar ; do
  echo "Waiting for undercloud..."
  sleep 30
done

for fff in __undercloud-install-1-as-root.sh __undercloud-install-2-as-stack-user.sh tripleo.mitaka.diff ; do
  scp $ssh_opts -B $fff ${ssh_addr}:/root/$fff
done
ssh -t $ssh_opts $ssh_addr "NUM=$NUM NETDEV=$NETDEV SKIP_SSH_TO_HOST_KEY=$SKIP_SSH_TO_HOST_KEY /root/__undercloud-install-1-as-root.sh"

# TODO: temporary solution - 'overcloud' directory will be moved to separate repository later
rm -f oc.tar
tar cvf oc.tar overcloud
scp $ssh_opts oc.tar ${ssh_addr}:/home/stack/oc.tar
scp $ssh_opts overcloud-install.sh ${ssh_addr}:/home/stack/overcloud-install.sh

echo "SSH into undercloud: ssh -t $ssh_opts $ssh_addr"
