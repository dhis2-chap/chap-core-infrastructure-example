#!/bin/bash

# Update and install necessary packages
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git unzip

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Add "ubuntu" user to the docker group
usermod -aG docker ubuntu

# Install UV (assuming it's a python package as no direct download source is provided)
apt-get install -y python3-pip
pip3 install uv

# Clone the chap-core repository
git clone https://github.com/dhis2-chap/chap-core /opt/chap-core

# Run UV sync
cd /opt/chap-core
uv sync
