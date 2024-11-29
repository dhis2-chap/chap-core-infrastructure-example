#!/bin/bash
#This file will first install LXD on the machine, before launching CHAP Core
cd "$(dirname "$0")"

bash ./mount-volume.sh

bash ./install-lxd.sh

bash ./deploy-chap-core.sh
