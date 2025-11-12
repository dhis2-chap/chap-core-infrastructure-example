#!/usr/bin/env bash
set -euo pipefail

SITE_NAME="helloworld"
WEB_ROOT="/var/www/${SITE_NAME}"
INDEX_FILE="${WEB_ROOT}/index.html"
DEBIAN_SITE_AVAIL="/etc/nginx/sites-available/${SITE_NAME}"
DEBIAN_SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
RHEL_SITE_CONF="/etc/nginx/conf.d/${SITE_NAME}.conf"
BACKEND_URL="http://127.0.0.1:3000/"

log()  { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*" >&2; }
err()  { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (use sudo)."
    exit 1
  fi
}

detect_family() {
  if grep -qiE 'ubuntu|debian' /etc/os-release; then
    echo "debian"
  elif grep -qiE 'rhel|centos|rocky|alma|fedora' /etc/os-release; then
    echo "rhel"
  else
    err "Unsupported distro. This script supports Debian/Ubuntu and RHEL-family."
    exit 1
  fi
}

install_nginx() {
  case "$FAMILY" in
    debian)
      log "Installing Nginx (apt)…"
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
      systemctl enable nginx || true
      ;;
    rhel)
      PKG_MGR="dnf"
      need_cmd dnf || PKG_MGR="yum"
      log "Installing Nginx (${PKG_MGR})…"
      ${PKG_MGR} install -y nginx
      systemctl enable nginx || true
      ;;
  esac
}

write_index() {
  log "Creating web root and index.html…"
  mkdir -p "${WEB_ROOT}"
  cat > "${INDEX_FILE}" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Hello</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
  <p>hello world</p>
</body>
</html>
HTML

  # set ownership to web user if present
  if id -u www-data >/dev/null 2>&1; then chown -R www-data:www-data "${WEB_ROOT}"; fi
  if id -u nginx >/dev/null 2>&1; then chown -R nginx:nginx "${WEB_ROOT}"; fi
}

nginx_conf_block() {
  cat <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Reverse proxy to local backend (optional; safe if backend is absent)
    location /api/ {
        proxy_pass         ${BACKEND_URL};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Connection        "";
    }

    # Simple hardening headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;
}
NGINX
}

configure_nginx() {
  log "Writing Nginx configuration…"
  case "$FAMILY" in
    debian)
      mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
      nginx_conf_block > "${DEBIAN_SITE_AVAIL}"
      ln -sfn "${DEBIAN_SITE_AVAIL}" "${DEBIAN_SITE_ENABLED}"
      # disable default if present
      rm -f /etc/nginx/sites-enabled/default || true
      ;;
    rhel)
      nginx_conf_block > "${RHEL_SITE_CONF}"
      ;;
  esac
}

selinux_adjust() {
  if need_cmd getenforce && [[ "$(getenforce)" == "Enforcing" ]]; then
    warn "SELinux enforcing detected; setting correct contexts and booleans…"
    need_cmd semanage || { warn "semanage not found; installing policycoreutils-python-utils/policycoreutils-python…"; 
      if [[ "$FAMILY" == "debian" ]]; then
        apt-get install -y policycoreutils-python-utils || true
      else
        (need_cmd dnf && dnf install -y policycoreutils-python-utils) || (need_cmd yum && yum install -y policycoreutils-python) || true
      fi
    }
    # allow nginx to read our web root and connect out for proxying
    semanage fcontext -a -t httpd_sys_content_t "${WEB_ROOT}(/.*)?" 2>/dev/null || true
    restorecon -Rv "${WEB_ROOT}" >/dev/null || true
    setsebool -P httpd_can_network_connect 1 || true
  fi
}

open_firewall() {
  # UFW (Debian/Ubuntu)
  if need_cmd ufw && ufw status | grep -qi "Status: active"; then
    log "Configuring UFW for HTTP…"
    ufw allow 'Nginx Full' || ufw allow 80/tcp || true
  fi

  # Firewalld (RHEL)
  if need_cmd firewall-cmd && systemctl is-active --quiet firewalld; then
    log "Configuring firewalld for HTTP…"
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --reload || true
  fi
}

start_nginx() {
  log "Testing Nginx configuration…"
  if ! nginx -t; then
    err "nginx -t failed. Check messages above."
    exit 1
  fi

  log "Starting (or reloading) Nginx…"
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx || systemctl restart nginx
  else
    systemctl start nginx
  fi

  sleep 1
  if systemctl is-active --quiet nginx; then
    log "Nginx is active."
  else
    err "Nginx failed to start. Last status:"
    systemctl status --no-pager nginx || true
    journalctl -u nginx --no-pager -n 50 || true
    exit 1
  fi
}

verify_http() {
  if need_cmd curl; then
    log "Verifying HTTP on localhost…"
    set +e
    HTTP_OUT="$(curl -sS http://127.0.0.1/)"
    CODE=$?
    set -e
    if [[ $CODE -eq 0 && "$HTTP_OUT" == *"<p>hello world</p>"* ]]; then
      log "Success! Received expected index content."
    else
      warn "Curl did not return expected content. Check networking or upstream firewall."
    fi
  else
    warn "curl not found; skipping HTTP verify."
  fi
}

main() {
  require_root
  FAMILY="$(detect_family)"
  install_nginx
  write_index
  configure_nginx
  selinux_adjust
  open_firewall
  start_nginx
  verify_http
  log "All done. Visit: http://<server-ip>/"
  log "API proxy: http://<server-ip>/api/ -> ${BACKEND_URL}"
}

main "$@"
