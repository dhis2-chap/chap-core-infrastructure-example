#!/bin/bash
cd "$(dirname "$0")"

sudo bash ./install-start-nginx.sh || exit 1

#If you are running on a server with enough space mounting a volume would not be necessary.
bash ./mount-volume.sh || exit 1

LATEST_STABLE=$(./get-latest-tag.sh)
echo "Latest stable tag is: $LATEST_STABLE"
#Install LXD, we do this before deploying CHAP Core, since we wipe the server for every deployment
bash ./install-lxd.sh || exit 1

#This would deploy CHAP Core
bash ./create-lxc-container-and-install-chap-core.sh "stable" "9000" "$LATEST_STABLE" || exit 1
bash ./create-lxc-container-and-install-chap-core.sh "master" "8000" "master" || exit 1
