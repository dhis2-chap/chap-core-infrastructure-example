#!/bin/bash

# Update package list and install prerequisites
sudo apt-get update
sudo apt install snapd

sudo snap install lxd
sudo snap refresh lxd

# Add current user to the lxd group
sudo usermod -aG lxd $USER

# Initialize LXD
cat configs/lxd_preseed | sudo lxd init --preseed


