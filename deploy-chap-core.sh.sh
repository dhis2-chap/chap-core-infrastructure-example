
sudo lxc launch ubuntu:20.04 chap-container

# Wait for the container to initialize
sleep 30 

# Upload the initialization script to the container
sudo lxc file push chap-core-lxd-container-init.sh chap-container/root/

# Make the script executable
sudo lxc exec chap-container -- chmod +x /root/chap-core-lxd-container-init.sh

# Run the initialization script within the container
sudo lxc exec chap-container -- /root/chap-core-lxd-container-init.sh