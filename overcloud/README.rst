Overview
========

This folder contains 'heat' templates and scripts for installing TripleO with ScaleIO.
This is a PoC for TripleO/RedHat Director deployment. It assumes that tripleo-heat-templates has an OS::TripleO::AllNodesExtraConfigPost resource in the overcloud.yaml resource.

Heat Files
==========

Here is the files for defining of ScaleIO deployment in the TripleO resources.

scaleio.yaml - Main resource for ScaleIO deployment. It defines steps, dependecies and script names to run.
scaleio-data.yaml - Resource with parameters definition for ScaleIO deployment.

scaleio-env.yaml - Environment file with resource's definition and main parameters for deployment of ScaleIO

swap-env.yaml and swap.yaml - two resources to switch on swap space on overcloud nodes.

Scripts
=======

Here is scripts for ScaleIO installation and configuring.

01_install_packages.sh
02_create_cluster.sh
03_configure_cluster.sh
04_configure_controllers.sh
05_configure_clients.sh
06_post_configure_cluster.sh
