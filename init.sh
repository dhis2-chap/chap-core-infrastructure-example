#!/bin/bash
cd "$(dirname "$0")"

bash ./install-start-nginx.sh

#If you are running on a server with enough space mounting a volume would not be necessary.
bash ./mount-volume.sh

#Install LXD, we do this before deploying CHAP Core, since we wipe the server for every deployment
bash ./install-lxd.sh

#This would deploy CHAP Core
bash ./create-lxc-container-and-install-chap-core.sh
