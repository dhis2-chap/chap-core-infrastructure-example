#!/usr/bin/env bash
set -euo pipefail

SITE_NAME="helloworld"
WEB_ROOT="/var/www/${SITE_NAME}"
INDEX_FILE="${WEB_ROOT}/index.html"
INDEX_SOURCE="$(dirname "$(realpath "$0")")/index.html"
DEBIAN_SITE_AVAIL="/etc/nginx/sites-available/${SITE_NAME}"
DEBIAN_SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
DEV_BACKEND_URL="http://127.0.0.1:8000/"
STABLE_BACKEND_URL="http://127.0.0.1:9000/"

log()  { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*" >&2; }
err()  { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (use: sudo bash $0)"
    exit 1
  fi
}

install_nginx() {
  log "Installing Nginx with apt…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  systemctl enable nginx || true
}

write_index() {
  log "Creating web root and copying index.html…"
  mkdir -p "${WEB_ROOT}"

  if [[ ! -f "${INDEX_SOURCE}" ]]; then
    err "index.html not found in the same folder as this script!"
    exit 1
  fi

  cp -f "${INDEX_SOURCE}" "${INDEX_FILE}"
  chown -R www-data:www-data "${WEB_ROOT}"
  log "Copied ${INDEX_SOURCE} -> ${INDEX_FILE}"
}

nginx_conf_block() {
  cat <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root ${WEB_ROOT};
    index index.html;

    # Serve static index.html
    location / {
        try_files \$uri \$uri/ =404;
    }

    # /dev -> proxy to internal 127.0.0.1:8000
    location /dev/ {
        proxy_pass         ${DEV_BACKEND_URL};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Connection        "";
    }

    # /stable -> proxy to internal 127.0.0.1:9000
    location /stable/ {
        proxy_pass         ${STABLE_BACKEND_URL};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Connection        "";
    }

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;
}
NGINX
}

configure_nginx() {
  log "Writing Nginx site config (Ubuntu layout)…"
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  nginx_conf_block > "${DEBIAN_SITE_AVAIL}"
  ln -sfn "${DEBIAN_SITE_AVAIL}" "${DEBIAN_SITE_ENABLED}"
  rm -f /etc/nginx/sites-enabled/default || true
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    log "Allowing HTTP through UFW…"
    ufw allow 'Nginx Full' || ufw allow 80/tcp || true
  fi
}

start_nginx() {
  log "Testing Nginx configuration…"
  nginx -t
  log "Starting/reloading Nginx…"
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx || systemctl restart nginx
  else
    systemctl start nginx
  fi
  systemctl --no-pager --full status nginx | sed -n '1,10p' || true
}

verify_http() {
  if command -v curl >/dev/null 2>&1; then
    log "Verifying localhost HTTP…"
    curl -I http://127.0.0.1/ || warn "Root not reachable"
    curl -I http://127.0.0.1/dev/ || warn "/dev not reachable"
    curl -I http://127.0.0.1/stable/ || warn "/stable not reachable"
  fi
}

main() {
  require_root
  install_nginx
  write_index
  configure_nginx
  open_firewall
  start_nginx
  verify_http
  log "✅ Done!"
  log "→ Root:   http://<server-ip>/"
  log "→ /dev:   http://<server-ip>/dev/ → ${DEV_BACKEND_URL}"
  log "→ /stable:http://<server-ip>/stable/ → ${STABLE_BACKEND_URL}"
}

main "$@"
