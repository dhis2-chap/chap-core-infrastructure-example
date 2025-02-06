#This script will be copied inside the LXC container and will install and start CHAP Core when executed.

# Update and install necessary packages
echo "Running apt-get update..."
sudo apt-get update

sudo apt-get install \
 ca-certificates \
 curl \
 gnupg \
  lsb-release

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Running apt-get update..."
sudo apt-get update

echo "Running apt-get install..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Clone the chap-core repository
#git clone -b dev https://github.com/dhis2-chap/chap-core /root/chap-core
git clone https://github.com/dhis2-chap/chap-core /root/chap-core

# Move .env file from root to chap-core directory
mv /root/.env /root/chap-core/

sleep 5

# Navigate to the chap-core directory
cd /root/chap-core

# Run Docker Compose
docker compose up -d

docker ps

sleep 10
