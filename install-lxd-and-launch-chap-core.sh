#!/bin/bash

# Update package list and install prerequisites
sudo apt-get update

if ! dpkg -l | grep -q lxd; then
  sudo apt-get install -y lxd
else
  echo "LXD is already installed."
fi

# Add current user to the lxd group
sudo usermod -aG lxd $USER

# Initialize LXD
sudo lxd init

echo "LXD installation and initialization complete. Please log out and log back in for group changes to take effect."


lxc launch ubuntu:20.04 chap-container

# Wait for the container to initialize
sleep 30 

# Upload the initialization script to the container
lxc file push chap-core-lxd-container-init.sh chap-container/root/

# Make the script executable
lxc exec chap-container -- chmod +x /root/lxd-container-init.sh

# Run the initialization script within the container
lxc exec chap-container -- /root/lxd-container-init.sh
