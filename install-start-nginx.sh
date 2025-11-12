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
SSL_CERT="/etc/ssl/chap-selfsigned.crt"
SSL_KEY="/etc/ssl/chap-selfsigned.key"

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
  log "Installing Nginx and OpenSSL…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx openssl
  systemctl enable nginx || true
}

generate_cert() {
  if [[ -f "$SSL_CERT" && -f "$SSL_KEY" ]]; then
    log "Self-signed certificate already exists, skipping generation."
    return
  fi

  log "Generating self-signed SSL certificate…"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_KEY" -out "$SSL_CERT" \
    -subj "/C=US/ST=Example/L=Example/O=Chap/OU=IT/CN=localhost"
  chmod 600 "$SSL_KEY"
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
}

nginx_conf_block() {
  cat <<NGINX
# HTTP server (redirect to HTTPS)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    server_name _;
    root ${WEB_ROOT};
    index index.html;

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # /dev -> proxy to 127.0.0.1:8000
    location /dev/ {
        proxy_pass         ${DEV_BACKEND_URL};
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }

    # /stable -> proxy to 127.0.0.1:9000
    location /stable/ {
        proxy_pass         ${STABLE_BACKEND_URL};
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;
}
NGINX
}

configure_nginx() {
  log "Writing Nginx HTTPS site config…"
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  nginx_conf_block > "${DEBIAN_SITE_AVAIL}"
  ln -sfn "${DEBIAN_SITE_AVAIL}" "${DEBIAN_SITE_ENABLED}"
  rm -f /etc/nginx/sites-enabled/default || true
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    log "Allowing HTTP/HTTPS through UFW…"
    ufw allow 'Nginx Full' || { ufw allow 80/tcp; ufw allow 443/tcp; }
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
}

verify_http() {
  if command -v curl >/dev/null 2>&1; then
    log "Verifying HTTPS…"
    curl -kI https://127.0.0.1/ || warn "Could not reach HTTPS endpoint"
  fi
}

main() {
  require_root
  install_nginx
  generate_cert
  write_index
  configure_nginx
  open_firewall
  start_nginx
  verify_http
  log "✅ Setup complete!"
  log "→ HTTPS site: https://<server-ip>/"
  log "→ /dev proxy: https://<server-ip>/dev/  → ${DEV_BACKEND_URL}"
  log "→ /stable proxy: https://<server-ip>/stable/  → ${STABLE_BACKEND_URL}"
  log "⚠️  Browser will warn about self-signed cert — that’s expected."
}

main "$@"
