#!/bin/bash -e

# NOTE: installs Mitaka version

# common setting from create_env.sh
NUM=${NUM:-0}

# on kvm host do once: create stack user, create home directory, add him to libvirtd group

((addr=172+NUM*10))

# wait for undercloud and copy images for overcloud to it. (images can be build manually but it's too long - use previously built images)
while ! scp -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B /home/stack/images.tar root@192.168.$addr.2:/tmp/images.tar ; do echo "Waiting for undercloud..." ; sleep 30 ; done

for fff in __undercloud-install-1-as-root.sh __undercloud-install-2-as-stack-user.sh ; do
  scp -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B $fff root@192.168.$addr.2:/root/$fff
done
ssh -t -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.$addr.2 "NUM=$NUM /root/__undercloud-install-1-as-root.sh"

# TODO: temporary solution - 'overcloud' directory will be moved to separate repository later
rm oc.tar
tar cvf oc.tar overcloud
sudo scp  -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null oc.tar root@192.168.$addr.2:/home/stack/oc.tar
sudo scp  -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null overcloud-install.sh root@192.168.$addr.2:/home/stack/overcloud-install.sh

echo "SSH into undercloud: ssh -t -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.$addr.2"
