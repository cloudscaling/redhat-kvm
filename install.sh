#!/bin/bash -ex

# on kvm host do once: create stack user, create home directory, add him to libvirtd group

# wait for undercloud and copy images for overcloud to it. (images can be build manually but it's too long - use previously built images)
while ! scp -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B /home/stack/images.tar root@192.168.172.2:/tmp/images.tar ; do echo "Waiting for undercloud..." ; sleep 30 ; done

scp -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -B undercloud-install.sh root@192.168.172.2:/root/undercloud-install.sh
ssh -i kp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.172.2 /root/undercloud-install.sh
