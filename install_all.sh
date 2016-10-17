#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

"$my_dir"/create_env.sh
"$my_dir"/undercloud-install.sh

BASE_ADDR=${BASE_ADDR:-172}
((env_addr=BASE_ADDR+NUM*10))
ip_addr="192.168.${env_addr}.2"
ssh_opts="-i $my_dir/kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_addr="root@${ip_addr}"
ssh -t $ssh_opts $ssh_addr "sudo -u stack NUM=$NUM DEPLOY=1 /home/stack/overcloud-install.sh"

if [[ -n "$SUDO_USER" ]] ; then
  chown $SUDO_USER "$my_dir/kp-$NUM"
fi
