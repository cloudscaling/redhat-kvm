#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NUM=0
poolname="rdimages"

source "$my_dir/functions"

delete_network management
delete_network provisioning
delete_network external

delete_domains
