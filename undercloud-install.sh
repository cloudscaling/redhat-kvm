#!/bin/bash -e

# TODO: next scripts use environment 0 (NUM=0) and install Mitaka version

# on kvm host do once: create stack user, create home directory, add him to libvirtd group

# wait for undercloud and copy images for overcloud to it. (images can be build manually but it's too long - use previously built images)
while ! scp -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B /home/stack/images.tar root@192.168.172.2:/tmp/images.tar ; do echo "Waiting for undercloud..." ; sleep 30 ; done

for fff in __undercloud-install-1-as-root.sh __undercloud-install-2-as-stack-user.sh ; do
  scp -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B $fff root@192.168.172.2:/root/$fff
done
ssh -t -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.172.2 /root/__undercloud-install-1-as-root.sh

# temporary solution - 'overcloud' directory will be moved to separate repository later
rm oc.tar
tar cvf oc.tar overcloud
sudo scp  -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null oc.tar root@192.168.172.2:/home/stack/oc.tar

echo "SSH into undercloud: ssh -t -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.172.2"
