Overview
========

This repository provides scripts for installing TripleO with ScaleIO on kvm host.
Only OpenStack Mitaka version is supported now.


Prepare steps
=============

- check that user 'stack' exists on the kvm host and he has home directory, and he is added to libvirtd group
- checkout this project


Files and parameters
====================

create_env.sh - creates machines/networks/volumes
clean_env.sh - removes all
undercloud-install.sh - installs undercloud on the undercloud machine
overcloud-install.sh - installs overcloud

overcloud directory contains environment/templates for TripleO/Heat.
This directory will be extracted from this repository.

most of script files has definition of 'NUM' variable at start.
It allows to use several environments.

also create_env.sh defines machines counts for each role


Install steps
=============

export NUM=0
sudo ./create_env.sh
sudo ./undercloud-install.sh
# address depends on NUM varaible. check previous output for exact address
sudo ssh -t -i kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.172.2

su - stack
./overcloud-install.sh

And then last command shows deploy command that can be used in current shell or in the screen utility


Instructions was used
=====================
- https://keithtenzer.com/2015/10/14/howto-openstack-deployment-using-tripleo-and-the-red-hat-openstack-director/
- http://docs.openstack.org/developer/tripleo-docs/index.html
- https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/7/html/Director_Installation_and_Usage/
- http://docs.openstack.org/developer/heat/template_guide/index.html
