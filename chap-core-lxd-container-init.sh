#!/bin/bash

# Update and install necessary packages
apt-get update -y
apt-get upgrade -y

# Add deadsnakes PPA for Python 3.10
add-apt-repository ppa:deadsnakes/ppa -y
apt-get update -y

# Install Python 3.10
apt-get install -y python3.10 python3.10-venv python3.10-dev
python3 --version

# Update alternatives to set Python 3.10 as the default
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
#apt-get install -y curl git unzip

# Install Docker
#curl -fsSL https://get.docker.com -o get-docker.sh
#sh get-docker.sh
#rm get-docker.sh

# Add "ubuntu" user to the docker group
#usermod -aG docker ubuntu

# Install UV (assuming it's a python package as no direct download source is provided)
apt-get install -y python3-pip
pip3 install uv

# Clone the chap-core repository
git clone https://github.com/dhis2-chap/chap-core /opt/chap-core

# Run UV sync
cd /opt/chap-core
uv sync
