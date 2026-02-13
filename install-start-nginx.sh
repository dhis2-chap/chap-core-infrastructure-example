#!/usr/bin/env bash
set -euo pipefail

SITE_NAME="chap-servers.dhis2.org"
SERVER_NAME="chap-servers.dhis2.org www.chap-servers.dhis2.org"
CERTBOT_EMAIL="herman@dhis2.org"   # email for Let's Encrypt registration

WEB_ROOT="/var/www/${SITE_NAME}"
INDEX_FILE="${WEB_ROOT}/index.html"
INDEX_SOURCE="$(dirname "$(realpath "$0")")/index.html"
DEBIAN_SITE_AVAIL="/etc/nginx/sites-available/${SITE_NAME}"
DEBIAN_SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
DEV_BACKEND_URL="http://127.0.0.1:8000/"
STABLE_BACKEND_URL="http://127.0.0.1:9000/"

# Logs: source path and (optional) bind mount path (used if AppArmor blocks direct access)
LOGS_SRC="/logs"
LOGS_BIND="${WEB_ROOT}/logs"
LOGS_ALIAS=""   # set dynamically after AppArmor/ACL checks

# TLS paths for chap-servers.dhis2.org (Let's Encrypt layout)
TLS_CERT="/etc/letsencrypt/live/chap-servers.dhis2.org/fullchain.pem"
TLS_KEY="/etc/letsencrypt/live/chap-servers.dhis2.org/privkey.pem"
ENABLE_TLS=0

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

install_certbot_and_issue() {
  log "Installing certbot and nginx plugin…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx || {
    warn "Could not install certbot/python3-certbot-nginx; HTTPS issuance will be skipped."
    return 0
  }

  # If certs already exist, don't re-issue
  if [[ -f "${TLS_CERT}" && -f "${TLS_KEY}" ]]; then
    log "Existing TLS certs found; skipping certbot issuance."
    return 0
  fi

  log "Running certbot to issue certificates for chap-servers.dhis2.org (non-interactive)…"
  if ! certbot certonly --nginx \
    -d chap-servers.dhis2.org -d www.chap-servers.dhis2.org \
    -m "${CERTBOT_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    -n; then
    warn "certbot failed to obtain certificates. Site will run HTTP-only for now."
  else
    log "certbot successfully obtained certificates."
  fi
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

check_tls_files() {
  if [[ -f "${TLS_CERT}" && -f "${TLS_KEY}" ]]; then
    ENABLE_TLS=1
    log "Found TLS certificate and key for chap-servers.dhis2.org."
  else
    ENABLE_TLS=0
    warn "TLS certificate/key not found at:"
    warn "  CERT: ${TLS_CERT}"
    warn "  KEY:  ${TLS_KEY}"
    warn "Configuring HTTP-only for now."
  fi
}

nginx_conf_block() {
  if [[ "${ENABLE_TLS}" -eq 1 ]]; then
    ############################
    # HTTPS + HTTP redirect
    ############################
    cat <<NGINX
# HTTP → HTTPS redirect for chap-servers.dhis2.org
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVER_NAME};

    # Redirect everything to HTTPS
    return 301 https://\$host\$request_uri;
}

# HTTPS server for chap-servers.dhis2.org
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name ${SERVER_NAME};

    # --- TLS configuration (Let's Encrypt layout) ---
    ssl_certificate     ${TLS_CERT};
    ssl_certificate_key ${TLS_KEY};

    # Optional but recommended when using certbot with nginx:
    # include /etc/letsencrypt/options-ssl-nginx.conf;
    # ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root ${WEB_ROOT};
    index index.html;

    # Serve static index.html
    location / {
        try_files \$uri \$uri/ =404;
    }

    # Allow /logs/, /logs, and /log -> all go to /logs/
    location ^~ /logs {
        # Redirect /log -> /logs/
        if (\$uri = "/log") {
            return 301 /logs/;
        }

        # Redirect /logs -> /logs/
        if (\$uri = "/logs") {
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
    # Optional: enable HSTS once you're sure HTTPS works and certs auto-renew:
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
NGINX
  else
    ############################
    # HTTP-only (no SSL yet)
    ############################
    cat <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVER_NAME};

    root ${WEB_ROOT};
    index index.html;

    # Serve static index.html
    location / {
        try_files \$uri \$uri/ =404;
    }

    # Allow /logs/, /logs, and /log -> all go to /logs/
    location ^~ /logs {
        # Redirect /log -> /logs/
        if (\$uri = "/log") {
            return 301 /logs/;
        }

        # Redirect /logs -> /logs/
        if (\$uri = "/logs") {
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
  fi
}

configure_nginx() {
  log "Writing Nginx site config for ${SITE_NAME} (Ubuntu layout)…"
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  nginx_conf_block > "${DEBIAN_SITE_AVAIL}"
  ln -sfn "${DEBIAN_SITE_AVAIL}" "${DEBIAN_SITE_ENABLED}"
  rm -f /etc/nginx/sites-enabled/default || true
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    log "Allowing HTTP/HTTPS through UFW…"
    ufw allow 'Nginx Full' || ufw allow 80/tcp || ufw allow 443/tcp || true
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
    curl -I http://127.0.0.1/ || warn "Root not reachable over HTTP"
    curl -I http://127.0.0.1/dev/ || warn "/dev not reachable over HTTP"
    curl -I http://127.0.0.1/stable/ || warn "/stable not reachable over HTTP"
    curl -I http://127.0.0.1/logs/ || warn "/logs not reachable over HTTP"

    if [[ "${ENABLE_TLS}" -eq 1 ]]; then
      log "Attempting HTTPS check against chap-servers.dhis2.org (may fail if DNS not pointing here)…"
      curl -Ik https://chap-servers.dhis2.org/ || warn "HTTPS check for https://chap-servers.dhis2.org/ failed"
    fi
  fi

  log "Verifying nginx can see files in ${LOGS_ALIAS} as www-data…"
  sudo -u www-data bash -c "ls -la '${LOGS_ALIAS}' || true"
  if [[ -d "${LOGS_ALIAS}" ]]; then
    sudo -u www-data bash -c "stat '${LOGS_ALIAS}' || true"
  else
    warn "Expected directory '${LOGS_ALIAS}' not found (check name/path)."
  fi
}

main() {
  require_root
  install_packages
  write_index
  ensure_logs_path
  set_acls_for_www_data
  ensure_bind_mount_if_needed

  # Try to get certs before generating nginx config
  install_certbot_and_issue
  check_tls_files

  configure_nginx
  open_firewall
  start_nginx
  verify_http

  log "✅ Done!"
  if [[ "${ENABLE_TLS}" -eq 1 ]]; then
    log "→ Root:    https://chap-servers.dhis2.org/"
    log "→ /dev:    https://chap-servers.dhis2.org/dev/    → ${DEV_BACKEND_URL}"
    log "→ /stable: https://chap-servers.dhis2.org/stable/ → ${STABLE_BACKEND_URL}"
    log "→ /logs:   https://chap-servers.dhis2.org/logs/   → ${LOGS_ALIAS}"
  else
    log "→ Root:    http://chap-servers.dhis2.org/ (HTTP-only, TLS issuance failed or not ready)"
    log "→ /dev:    http://chap-servers.dhis2.org/dev/     → ${DEV_BACKEND_URL}"
    log "→ /stable: http://chap-servers.dhis2.org/stable/  → ${STABLE_BACKEND_URL}"
    log "→ /logs:   http://chap-servers.dhis2.org/logs/    → ${LOGS_ALIAS}"
  fi
}

main "$@"
