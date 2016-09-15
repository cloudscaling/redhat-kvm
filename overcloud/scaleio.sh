#!/bin/bash -e

env | sort >> /var/log/scaleio-2.log

echo "$(hostname)" >> /var/log/scaleio-2.log
