#!/bin/bash -e

url=$(hiera scaleio::packages_source_url)
echo "$url" >> /var/log/scaleio.log
curl $url >> /var/log/scaleio.log
