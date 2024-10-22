#!/bin/bash

# Update and install necessary packages
apt-get update -y
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Clone the chap-core repository
git clone -b dev https://github.com/dhis2-chap/chap-core /opt/chap-core

# Navigate to the chap-core directory
cd /opt/chap-core

# Run Docker Compose
docker compose up -d

