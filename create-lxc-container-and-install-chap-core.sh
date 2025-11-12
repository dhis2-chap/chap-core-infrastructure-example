#!/bin/bash

VERSION="$1"
EXPOSE_PORT="$2"
BRANCH_OR_TAG="$3"

CONTAINER_NAME="chap-core-$VERSION"
DOCKER_NAME="docker-$VERSION"

lxc storage create $DOCKER_NAME btrfs size=40GB

sleep 10

echo "Creating LXC container: $CONTAINER_NAME"

sudo lxc launch ubuntu:24.04 $CONTAINER_NAME

wait 4

lxc storage volume create $DOCKER_NAME $CONTAINER_NAME size=40GB
lxc config device add $CONTAINER_NAME docker disk pool=$DOCKER_NAME source=$CONTAINER_NAME path=/var/lib/docker || exit 1

lxc config set $CONTAINER_NAME security.nesting=true security.syscalls.intercept.mknod=true security.syscalls.intercept.setxattr=true


# As explained in the documentation, we do not want to expose the CHAP Core URL/IP address, since this will allow anyone to access the CHAP Core API.
# This repo is used for testing, and we only send test data to it, which is not sensitive. Therefore, we expose the CHAP Core URL/IP address.
# DO NOT DO SET "FOR_TESTING = TRUE" IF YOU HAVE DATA YOU DO NOT WANT TO BE PUBLICLY ACCESSIBLE.
if [ "$FOR_TESTING" = "TRUE" ]; then
  sudo lxc config device add $CONTAINER_NAME port-$EXPOSE_PORT proxy listen=tcp:127.0.0.1:8000 connect=tcp:127.0.0.1:$EXPOSE_PORT
fi

# Wait for the container to initialize
sleep 10

# Upload the initialization script to the container
sudo lxc file push install-chap-core-inside-lxc.sh $CONTAINER_NAME/root/

# Create .env file with secrets
echo "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY=$GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY" > .env
echo "GOOGLE_SERVICE_ACCOUNT_EMAIL=$GOOGLE_SERVICE_ACCOUNT_EMAIL" >> .env

# Push the .env file to the container, will later be pushed into chap-core directory
sudo lxc file push .env $CONTAINER_NAME/root/

# Make the script executable
sudo lxc exec $CONTAINER_NAME -- chmod +x /root/install-chap-core-inside-lxc.sh

# Run the initialization script within the container, this will intall CHAP Core inside the LXC container
sudo lxc exec $CONTAINER_NAME -- /root/install-chap-core-inside-lxc.sh $BRANCH_OR_TAG