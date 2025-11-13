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

# Logs: source path and (optional) bind mount path (used if AppArmor blocks direct access)
LOGS_SRC="/home/ubuntu/chap-core/logs"
LOGS_BIND="${WEB_ROOT}/logs"
LOGS_ALIAS=""   # set dynamically after AppArmor/ACL checks

log()  { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*" >&2; }
err()  { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (use: sudo bash $0)"
    exit 1
  fi
}

install_packages() {
  log "Installing required packages (nginx, acl, apparmor-utils if available)…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx acl || true
  # apparmor-utils provides aa-status; not fatal if absent
  DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils || true
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

ensure_logs_path() {
  log "Ensuring logs source path exists: ${LOGS_SRC}"
  mkdir -p "${LOGS_SRC}"
}

set_acls_for_www_data() {
  log "Granting www-data traverse/read ACLs for logs path…"
  # Traverse on parents
  setfacl -m u:www-data:rx /home || true
  setfacl -m u:www-data:rx /home/ubuntu || true
  setfacl -m u:www-data:rx /home/ubuntu/chap-core || true
  setfacl -m u:www-data:rx "${LOGS_SRC}" || true
  # Read/execute on everything inside logs (X = only directories + exec bits)
  setfacl -R -m u:www-data:rX "${LOGS_SRC}" || true
}

apparmor_enforcing_for_nginx() {
  if command -v aa-status >/dev/null 2>&1; then
    # If aa-status output mentions nginx in enforce mode, return 0
    if aa-status 2>/dev/null | grep -qiE 'nginx.*enforce'; then
      return 0
    fi
  fi
  return 1
}

ensure_bind_mount_if_needed() {
  if apparmor_enforcing_for_nginx; then
    log "AppArmor enforcing for nginx detected. Using bind mount under ${LOGS_BIND}…"
    mkdir -p "${LOGS_BIND}"
    # Bind mount if not already mounted
    if ! mountpoint -q "${LOGS_BIND}"; then
      mount --bind "${LOGS_SRC}" "${LOGS_BIND}"
      log "Bind-mounted ${LOGS_SRC} -> ${LOGS_BIND}"
    else
      log "Bind mount already active at ${LOGS_BIND}"
    fi

    # Persist bind mount in /etc/fstab (idempotent)
    FSTAB_LINE="${LOGS_SRC} ${LOGS_BIND} none bind 0 0"
    if ! grep -qsF "${FSTAB_LINE}" /etc/fstab; then
      printf "%s\n" "${FSTAB_LINE}" >> /etc/fstab
      log "Added bind mount to /etc/fstab"
    else
      log "Bind mount already present in /etc/fstab"
    fi

    LOGS_ALIAS="${LOGS_BIND}"
  else
    LOGS_ALIAS="${LOGS_SRC}"
  fi
  log "Logs alias target: ${LOGS_ALIAS}"
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
    
    # Allow /logs/, /logs, and /log -> all go to /logs/
    location ^~ /logs {
        # Redirect /log -> /logs/
        if ($uri = "/log") {
            return 301 /logs/;
        }

        # Redirect /logs -> /logs/
        if ($uri = "/logs") {
            return 301 /logs/;
        }

        alias ${LOGS_ALIAS}/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        # Prevent access to dotfiles
        location ~ /\. {
            deny all;
        }
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
    curl -I http://127.0.0.1/logs/ || warn "/logs not reachable"
  fi

  log "Verifying nginx can see files in ${LOGS_ALIAS} as www-data…"
  sudo -u www-data bash -c "ls -la '${LOGS_ALIAS}' || true"
  if [[ -f "${LOGS_ALIAS}" ]]; then
    sudo -u www-data bash -c "stat '${LOGS_ALIAS}' || true"
  else
    warn "Expected file '${LOGS_ALIAS}' not found (check name/path)."
  fi
}

main() {
  require_root
  install_packages
  write_index
  ensure_logs_path
  set_acls_for_www_data
  ensure_bind_mount_if_needed
  configure_nginx
  open_firewall
  start_nginx
  verify_http
  log "✅ Done!"
  log "→ Root:    http://<server-ip>/"
  log "→ /dev:    http://<server-ip>/dev/    → ${DEV_BACKEND_URL}"
  log "→ /stable: http://<server-ip>/stable/ → ${STABLE_BACKEND_URL}"
  log "→ /logs:   http://<server-ip>/logs/   → ${LOGS_ALIAS}"
}

main "$@"
