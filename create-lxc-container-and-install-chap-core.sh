#!/bin/bash
set -euo pipefail

VERSION="$1"
EXPOSE_PORT="$2"
BRANCH_OR_TAG="$3"

CONTAINER_NAME="chap-core-$VERSION"
DOCKER_NAME="docker-$VERSION"

# Create storage pool (ignore if it already exists)
sudo lxc storage create "$DOCKER_NAME" btrfs size=40GB || true

sleep 10

echo "Creating LXC container: $CONTAINER_NAME"
sudo lxc launch ubuntu:24.04 "$CONTAINER_NAME" \
  -c security.nesting=true \
  -c security.privileged=true

sleep 4

# Storage volume for Docker-in-LXC
sudo lxc storage volume create "$DOCKER_NAME" "$CONTAINER_NAME" size=40GB || true
sudo lxc config device add "$CONTAINER_NAME" docker disk \
  pool="$DOCKER_NAME" source="$CONTAINER_NAME" path=/var/lib/docker || true

# Extra config for nested Docker: relax AppArmor & keep intercepts
sudo lxc config set "$CONTAINER_NAME" \
  raw.lxc="lxc.apparmor.profile=unconfined" \
  security.syscalls.intercept.mknod=true \
  security.syscalls.intercept.setxattr=true

# Optional: port proxy for testing
if [ "${FOR_TESTING:-}" = "TRUE" ]; then
  sudo lxc config device add "$CONTAINER_NAME" "port-$EXPOSE_PORT" proxy \
    listen=tcp:127.0.0.1:"$EXPOSE_PORT" connect=tcp:127.0.0.1:8000 || true
fi

sleep 10

sudo lxc file push install-chap-core-inside-lxc.sh "$CONTAINER_NAME"/root/

cat > .env <<EOF
GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY=$GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY
GOOGLE_SERVICE_ACCOUNT_EMAIL=$GOOGLE_SERVICE_ACCOUNT_EMAIL
POSTGRES_USER=${POSTGRES_USER:-chap}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-chap}
POSTGRES_DB=${POSTGRES_DB:-chap}
EOF

sudo lxc file push .env "$CONTAINER_NAME"/root/
rm .env

sudo lxc exec "$CONTAINER_NAME" -- chmod +x /root/install-chap-core-inside-lxc.sh

HOST_LOG_DIR=/logs/chap-core-"$VERSION"
sudo mkdir -p "$HOST_LOG_DIR"
sudo chmod 777 "$HOST_LOG_DIR"

sudo lxc config device add "$CONTAINER_NAME" chap-logs disk \
  source="$HOST_LOG_DIR" path=/root/logs || true

sudo lxc exec "$CONTAINER_NAME" -- /root/install-chap-core-inside-lxc.sh "$BRANCH_OR_TAG"
