
lxc storage create docker btrfs size=90GB
sleep 10
sudo lxc launch ubuntu:24.04 chap-core

# Create new storage volume
lxc storage volume create docker chap-core size=90GB
lxc config device add chap-core docker disk pool=docker source=chap-core path=/var/lib/docker
lxc config set chap-core security.nesting=true security.syscalls.intercept.mknod=true security.syscalls.intercept.setxattr=true

# set environment variables
lxc config set chap-core environment.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY "$GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY"
lxc config set chap-core environment.GOOGLE_SERVICE_ACCOUNT_EMAIL "$GOOGLE_SERVICE_ACCOUNT_EMAIL"
lxc exec chap-core -- env

lxc restart chap-core

# As explained in the documentation, we do not want to expose the CHAP Core URL/IP address, since this will allow anyone to access the CHAP Core API.
# This repo is used for testing, and we only send test data to it, which is not sensitive. Therefore, we expose the CHAP Core URL/IP address.
# DO NOT DO SET "FOR_TESTING = TRUE" IF YOU HAVE DATA YOU DO NOT WANT TO BE PUBLICLY ACCESSIBLE.
if [ "$FOR_TESTING" = "TRUE" ]; then
  sudo lxc config device add chap-core chapPort443 proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:8000
fi


# Wait for the container to initialize
sleep 30 

# Upload the initialization script to the container
sudo lxc file push chap-core-lxd-container-init.sh chap-core/root/

# Make the script executable
sudo lxc exec chap-core -- chmod +x /root/chap-core-lxd-container-init.sh

# Run the initialization script within the container
sudo lxc exec chap-core -- /root/chap-core-lxd-container-init.sh
