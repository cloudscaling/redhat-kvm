#!/bin/bash -e

source /etc/scaleio.env
url=$PackagesSourceURL
echo "$url" >> /var/log/scaleio.log
curl $url >> /var/log/scaleio.log
