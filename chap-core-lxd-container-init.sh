#!/bin/bash

# Update and install necessary packages
sudp apt-get update -y
sudp apt-get upgrade -y

sudo apt-get install \
 ca-certificates \
 curl \
 gnupg \
  lsb-release

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg \
--dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Clone the chap-core repository
git clone https://github.com/dhis2-chap/chap-core /root/chap-core

# Navigate to the chap-core directory
cd /root/chap-core

# Run Docker Compose
docker compose up -d

