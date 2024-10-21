#This file will first install LXD on the machine, before launching CHAP Core
# Install LXD

# Clone the infrastructure repository, this will be used to deploy CHAP Core lxd container
./fetch-infrastructure.sh

./install-lxd.sh

./deploy-chap-core.sh
