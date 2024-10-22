
# Check if the container exists and delete it if it does
if sudo lxc list | grep -q "chap-container"; then
  echo "Deleting existing container..."
  sudo lxc delete chap-container --force
fi

sleep 10
# Delete existing storage pool
sudo lxc storage volume delete docker chap-container
# Wait for the container to be deleted
sleep 10
# Delete the storage pool
sudo lxc storage delete docker

# Wait for the storage pool to be deleted
sleep 1+

lxc storage create docker btrfs
sudo lxc launch ubuntu:20.04 chap-container

# Delete existing storage volume if it exists


# Create new storage volume
lxc storage volume create docker chap-container
lxc config device add chap-container docker disk pool=docker source=chap-container path=/var/lib/docker
lxc config set chap-container security.nesting=true security.syscalls.intercept.mknod=true security.syscalls.intercept.setxattr=true

lxc restart chap-container

sudo lxc config device add chap-container myport8080 proxy listen=tcp:0.0.0.0:8080 connect=tcp:127.0.0.1:8000

# Wait for the container to initialize
sleep 30 

# Upload the initialization script to the container
sudo lxc file push chap-core-lxd-container-init.sh chap-container/root/

# Make the script executable
sudo lxc exec chap-container -- chmod +x /root/chap-core-lxd-container-init.sh

# Run the initialization script within the container
sudo lxc exec chap-container -- /root/chap-core-lxd-container-init.sh