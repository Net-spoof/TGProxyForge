write_site() {
  mkdir -p "$SITE_DIR"
  cat >"$SITE_DIR/index.html" <<'EOF_HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Service Online</title><style>body{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#e2e8f0;display:grid;place-items:center;min-height:100vh;margin:0}.c{max-width:680px;padding:40px;border:1px solid #334155;border-radius:22px;background:#111827;box-shadow:0 25px 60px #0006}h1{margin-top:0;color:#38bdf8}.s{color:#94a3b8}code{color:#86efac}</style></head><body><main class="c"><h1>Service Online</h1><p>This endpoint is available over HTTPS.</p><p class="s">Powered by a standard TLS web front.</p></main></body></html>
EOF_HTML
  chmod 755 "$SITE_DIR"; chmod 644 "$SITE_DIR/index.html"
}

patch_tproxy_checkout_ports() {
  local root=$1
  python3 - "$root" "$RELAY_PORT" "$ADMIN_PORT" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); relay=sys.argv[2]; admin=sys.argv[3]
for rel in ["deploy/install.sh","deploy/Caddyfile"]:
    p=root/rel
    s=p.read_text()
    s=s.replace("127.0.0.1:8080", f"127.0.0.1:{relay}")
    s=s.replace("127.0.0.1:8081", f"127.0.0.1:{admin}")
    p.write_text(s)
PY
}

install_web_stack() {
  log "Installing official WEB proxy stack (tproxy-server + MTProxy + Caddy)..."
  mkdir -p "$SRC_DIR"
  rm -rf "$SRC_DIR/tproxy-server"
  git init -q "$SRC_DIR/tproxy-server"
  git -C "$SRC_DIR/tproxy-server" remote add origin https://github.com/telegramdesktop/tproxy-server.git
  git -C "$SRC_DIR/tproxy-server" fetch -q --depth 1 origin "$TPROXY_COMMIT"
  git -C "$SRC_DIR/tproxy-server" checkout -q --detach FETCH_HEAD
  patch_tproxy_checkout_ports "$SRC_DIR/tproxy-server"
  write_site

  bash "$SRC_DIR/tproxy-server/deploy/install.sh" \
    --hostname "$DOMAIN" \
    --email "$ACME_EMAIL" \
    --site-dir "$SITE_DIR" \
    --base-path none \
    --secret "dd${BASE_SECRET}"
}

install_telemt() {
  log "Installing Telemt ${TELEMT_VERSION}..."
  [[ $(uname -m) == x86_64 ]] || die "This release currently supports x86_64 only."
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fL --retry 4 --connect-timeout 15 \
    "https://github.com/telemt/telemt/releases/download/${TELEMT_VERSION}/telemt-x86_64-linux-gnu.tar.gz" \
    -o "$tmp/telemt.tar.gz"
  echo "${TELEMT_AMD64_SHA256}  $tmp/telemt.tar.gz" | sha256sum -c -
  tar -xzf "$tmp/telemt.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/telemt" "$TELEMT_BIN"
  rm -rf "$tmp"
  trap - RETURN

  id telemt >/dev/null 2>&1 || useradd --system --user-group --home-dir "$APP_DIR/telemt" --create-home --shell /usr/sbin/nologin telemt
  # tgproxy uses umask 077. Without explicit directory permissions, the
  # telemt service account cannot traverse /etc/telemt to read its TOML.
  install -d -o root -g telemt -m 0750 /etc/telemt
  install -d -o telemt -g telemt -m 0750 "$APP_DIR/telemt"

  cat >"$TELEMT_UNIT" <<EOF_UNIT
[Unit]
Description=TGProxyForge Telemt FakeTLS Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=$APP_DIR/telemt
ExecStart=$TELEMT_BIN $TELEMT_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF_UNIT
  systemctl daemon-reload
  systemctl enable telemt >/dev/null
}

render_telemt() {
  local mask_port=443 use_me=false ad_line=''
  [[ $FAKETLS_PORT -eq 443 ]] && mask_port=8443
  if [[ $SPONSOR_ENABLED == 1 ]]; then
    use_me=true
    ad_line="ad_tag = \"${ADTAG}\""
  fi

  # Also repair permissions on already installed machines when 'tgproxy apply'
  # is used. The group requires directory execute permission to read the file.
  install -d -o root -g telemt -m 0750 /etc/telemt
  cat >"$TELEMT_CFG" <<EOF_TOML
[general]
use_middle_proxy = $use_me
$ad_line
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "$DOMAIN"
public_port = $FAKETLS_PORT

[network]
ipv4 = true
ipv6 = false
prefer = 4

[server]
port = $FAKETLS_PORT

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32", "::1/128"]

[censorship]
tls_domain = "$DOMAIN"
mask = true
mask_host = "127.0.0.1"
mask_port = $mask_port
unknown_sni_action = "mask"
tls_emulation = false
fake_cert_len = 2048

[access]
replay_check_len = 65536
ignore_time_skew = false

[access.users]
main = "$BASE_SECRET"
EOF_TOML
  chown root:telemt "$TELEMT_CFG"
  chmod 0640 "$TELEMT_CFG"
}

render_tproxy() {
  mkdir -p /etc/tproxy-server
  cat >"$TPROXY_CFG" <<EOF_JSON
{
  "public_hostname": "$DOMAIN",
  "base_path": "",
  "listen": "127.0.0.1:$RELAY_PORT",
  "admin_listen": "127.0.0.1:$ADMIN_PORT",
  "public_dir": "/srv/tproxy-site",
  "static_routes": "exact",
  "profiles_file": "/run/credentials/tproxy-server.service/profiles.json"
}
EOF_JSON
  cat >"$TPROXY_PROFILES" <<EOF_JSON
{"profiles":[{"name":"default","secret":"dd${BASE_SECRET}","backend":"127.0.0.1:2398"}]}
EOF_JSON
  chown root:tproxy "$TPROXY_CFG" "$TPROXY_PROFILES" 2>/dev/null || true
  chmod 0640 "$TPROXY_CFG"; chmod 0400 "$TPROXY_PROFILES"
}

render_mtproxy_sponsor() {
  [[ -f $MTPROXY_ENV ]] || return 0
  sed -i '/^MTPROXY_SECRET=/d;/^MTPROXY_ADTAG_ARGS=/d' "$MTPROXY_ENV"
  printf 'MTPROXY_SECRET=%s\n' "$BASE_SECRET" >>"$MTPROXY_ENV"
  if [[ $SPONSOR_ENABLED == 1 ]]; then
    printf 'MTPROXY_ADTAG_ARGS=-P %s\n' "$ADTAG" >>"$MTPROXY_ENV"
  else
    printf 'MTPROXY_ADTAG_ARGS=\n' >>"$MTPROXY_ENV"
  fi

  mkdir -p "$(dirname "$MTPROXY_OVERRIDE")"
  cat >"$MTPROXY_OVERRIDE" <<'EOF_UNIT'
[Service]
ExecStart=
ExecStart=/opt/MTProxy/objs/bin/mtproto-proxy -u mtproxy -p 8888 -H 2398 -S ${MTPROXY_SECRET} $MTPROXY_ADTAG_ARGS $MTPROXY_NAT_ARGS --aes-pwd /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf -M ${MTPROXY_WORKERS} -C ${MTPROXY_MAX_CONNECTIONS}
EOF_UNIT
}

render_caddy() {
  mkdir -p /etc/caddy
  if [[ $FAKETLS_PORT -eq 443 ]]; then
    cat >"$CADDY_CFG" <<EOF_CADDY
{
  email $ACME_EMAIL
  admin off
  servers {
    protocols h1 h2
  }
}

http://$DOMAIN {
  redir https://$DOMAIN{uri} permanent
}

https://$DOMAIN:8443 {
  bind 127.0.0.1
  encode zstd gzip
  header {
    -Via
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
  }
  reverse_proxy 127.0.0.1:$RELAY_PORT {
    transport http {
      response_header_timeout 40s
    }
  }
}
EOF_CADDY
  else
    cat >"$CADDY_CFG" <<EOF_CADDY
{
  email $ACME_EMAIL
  admin off
  servers {
    protocols h1 h2
  }
}

$DOMAIN {
  encode zstd gzip
  header {
    -Via
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
  }
  reverse_proxy 127.0.0.1:$RELAY_PORT {
    transport http {
      response_header_timeout 40s
    }
  }
}
EOF_CADDY
  fi
}

write_caddy_env() {
  mkdir -p /etc/systemd/system/caddy.service.d
  cat >/etc/systemd/system/caddy.service.d/tproxy.conf <<EOF_UNIT
[Service]
Environment=TPROXY_HOSTNAME=$DOMAIN
Environment=TPROXY_SITE_ROOT=/srv/tproxy-site
Environment=ACME_EMAIL=$ACME_EMAIL
EOF_UNIT
}

apply_config() {
  load_config
  render_telemt
  render_tproxy
  render_mtproxy_sponsor
  render_caddy
  write_caddy_env
  systemctl daemon-reload
  /usr/local/bin/tproxy-server -config "$TPROXY_CFG" -profiles-file "$TPROXY_PROFILES" -check >/dev/null
  /usr/local/bin/caddy validate --config "$CADDY_CFG" --adapter caddyfile >/dev/null

  # Port ownership changes when FakeTLS moves to/from 443. Stop both frontends
  # before starting them with the new layout so they never race for :443.
  systemctl stop telemt caddy 2>/dev/null || true
  systemctl restart tproxy-server mtproxy
  systemctl start caddy
  systemctl start telemt
  verify_stack_ready
}

telemt_has_listener() {
  ss -H -lntp | awk -v p=":$FAKETLS_PORT" '$4 ~ (p "$") && /telemt/ {found=1} END {exit !found}'
}

verify_stack_ready() {
  # systemctl start reports success once a process starts. Telemt may exit
  # immediately afterwards (e.g. inaccessible config directory). Wait for
  # its real listener and API before declaring the installation successful.
  local i
  log "Verifying service readiness, FakeTLS :$FAKETLS_PORT ..."
  for i in $(seq 1 45); do
    if systemctl is-active --quiet telemt &&
       systemctl is-active --quiet caddy &&
       systemctl is-active --quiet tproxy-server &&
       systemctl is-active --quiet mtproxy &&
       telemt_has_listener &&
       curl -fsS --max-time 2 http://127.0.0.1:9091/v1/users >/dev/null 2>&1 &&
       curl -fsS --max-time 2 "http://127.0.0.1:${ADMIN_PORT}/readyz" >/dev/null 2>&1; then
      ok "Telemt listener, API, WEB relay and all services are ready."
      return 0
    fi
    sleep 1
  done
  warn "Startup failed: one or more required services are not ready."
  systemctl --no-pager --full status telemt caddy mtproxy tproxy-server >&2 || true
  journalctl -u telemt -n 70 --no-pager >&2 || true
  warn "Current listeners:"
  ss -lntp >&2 || true
  return 1
}
