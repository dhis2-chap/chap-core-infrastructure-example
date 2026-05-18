#!/bin/bash
set -euo pipefail

BRANCH_OR_TAG="$1"

LOG_DIR=/root/logs
mkdir -p "$LOG_DIR"

SAFE_BRANCH=${BRANCH_OR_TAG//\//_}
LOG_FILE="$LOG_DIR/chap-core-${SAFE_BRANCH}.txt"

# Send all output to both the log file and stdout
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Running apt-get update..."
apt-get update -y

echo "Installing base packages..."
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

echo "Running apt-get update (Docker repo)..."
apt-get update -y

echo "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io=1.7.28-1~ubuntu.24.04~noble docker-compose-plugin

# Clone the repo
cd /root
git clone --depth 1 --branch "$BRANCH_OR_TAG" https://github.com/dhis2-chap/chap-core.git

cp /root/.env /root/chap-core/ || true

cd /root/chap-core

echo "Starting Docker Compose for branch/tag: ${BRANCH_OR_TAG}"

# Mirror chap-core's `make restart` semantics: include the chapkit overlay
# when the checked-out branch/tag ships it. Today: master only; stable will
# adopt it in 2.0. No script change needed when that happens.
COMPOSE_FILES=(-f compose.yml)
if [[ -f compose.chapkit.yml ]]; then
  COMPOSE_FILES+=(-f compose.chapkit.yml)
  echo "chapkit overlay detected; including compose.chapkit.yml"
fi

docker compose "${COMPOSE_FILES[@]}" up -d --build --remove-orphans

docker compose logs --tail=200

docker ps
