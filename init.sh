#!/bin/bash
cd "$(dirname "$0")"

sudo bash ./install-start-nginx.sh || exit 1

#If you are running on a server with enough space mounting a volume would not be necessary.
bash ./mount-volume.sh || exit 1

#Install LXD, we do this before deploying CHAP Core, since we wipe the server for every deployment
bash ./install-lxd.sh || exit 1

bash ./install-docker-storage.sh || exit 1

#This would deploy CHAP Core
bash ./create-lxc-container-and-install-chap-core.sh || exit 1
