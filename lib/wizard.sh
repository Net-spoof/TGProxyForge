wizard() {
  need_root
  if [[ -f $CONFIG_FILE ]]; then
    die "TGProxyForge is already configured on this server. Run: tgproxy"
  fi
  [[ -f /etc/os-release ]] || die "Unsupported operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  case ${ID:-} in ubuntu|debian) ;; *) die "Supported: Ubuntu 22.04+/24.04+ or Debian 12+ (x86_64).";; esac
  [[ $(uname -m) == x86_64 ]] || die "x86_64 is currently required by the WEB proxy backend."

  printf "%b%s — interactive installer%b\n" "$C_BOLD$C_CYAN" "$APP_NAME" "$C_RESET"
  hr
  install_prereqs

  local first domain ip port email sponsor=0 auto_domain=0
  read -r -p "Server public IP or proxy domain: " first
  first=${first,,}
  if is_ipv4 "$first"; then
    ip="$first"
    while true; do
      read -r -p "Your domain (press Enter for free auto-generated hostname): " domain
      domain=${domain,,}
      if [[ -z $domain ]]; then
        auto_domain=1
        domain="$(auto_proxy_domain "$ip")"
        log "Auto hostname: $domain -> $ip (via third-party sslip.io DNS)"
        warn "Automatic DNS depends on sslip.io availability, resolvers, and successful public TLS certificate issuance."
        break
      fi
      is_domain "$domain" && break
      warn "Enter a valid lowercase domain, e.g. proxy.example.com, or press Enter for auto hostname."
    done
  elif is_domain "$first"; then
    domain="$first"
    ip="$(detect_public_ip || true)"
    [[ -n $ip ]] || ip="$(resolve_domain_ip "$domain")"
    is_ipv4 "$ip" || die "Could not determine the server public IPv4."
  else
    die "Input must be a valid IPv4 address or DNS hostname."
  fi

  local dns_ip
  dns_ip="$(resolve_domain_ip "$domain")"
  if [[ $auto_domain == 1 && $dns_ip != "$ip" ]]; then
    die "Automatic hostname $domain did not resolve to $ip (got: ${dns_ip:-no DNS result}). Check DNS access or retry with your own domain. No changes have been made to proxy services."
  elif [[ -z $dns_ip ]]; then
    warn "The domain currently has no IPv4 A record. Create: $domain -> $ip before certificate issuance."
    prompt_yes_no "Continue anyway?" n || exit 1
  elif [[ $dns_ip != "$ip" ]]; then
    warn "DNS mismatch: $domain resolves to $dns_ip but this server is $ip"
    prompt_yes_no "Continue anyway?" n || exit 1
  else
    ok "DNS: $domain -> $ip"
  fi

  while true; do
    read -r -p "FakeTLS port [443]: " port
    port=${port:-443}
    valid_port "$port" || { warn "Invalid port."; continue; }
    [[ $port -ne 80 ]] || { warn "Port 80 is reserved for ACME/HTTP."; continue; }
    break
  done

  if [[ $auto_domain == 1 ]]; then
    read -r -p "Your real email for HTTPS certificate notifications: " email
  else
    read -r -p "ACME email [admin@$domain]: " email
    email=${email:-admin@$domain}
  fi
  [[ $email =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "Invalid email."

  if prompt_yes_no "Enable sponsored/promoted channel support?" y; then sponsor=1; fi

  DOMAIN="$domain"; SERVER_IP="$ip"; AUTO_DOMAIN="$auto_domain"; FAKETLS_PORT="$port"; ACME_EMAIL="$email"
  BASE_SECRET="$(random_secret)"; SPONSOR_ENABLED=0; ADTAG=''
  RELAY_PORT="$(choose_loopback_port 18080)"
  ADMIN_PORT="$(choose_loopback_port $((RELAY_PORT+1)))"
  [[ $ADMIN_PORT != "$RELAY_PORT" ]] || ADMIN_PORT="$(choose_loopback_port $((RELAY_PORT+2)))"

  mkdir -p "$APP_DIR" "$SRC_DIR" "$BACKUP_DIR" "$STATE_DIR"
  chmod 0755 "$APP_DIR" "$SRC_DIR" "$BACKUP_DIR"
  save_config

  echo
  hr
  echo "Installation plan"
  echo "Hostname       : $DOMAIN"
  echo "Hostname mode  : $([[ $AUTO_DOMAIN == 1 ]] && echo 'auto (sslip.io; external dependency)' || echo 'own domain')"
  echo "Public IPv4    : $SERVER_IP"
  echo "FakeTLS port   : $FAKETLS_PORT"
  echo "WEB HTTPS port : 443"
  echo "WEB relay      : 127.0.0.1:$RELAY_PORT / admin :$ADMIN_PORT"
  echo "Base secret    : $BASE_SECRET"
  hr
  prompt_yes_no "Start installation?" y || exit 0

  # Protect existing installations before the upstream installer replaces configs.
  for p in /etc/caddy/Caddyfile /etc/tproxy-server /etc/mtproxy /etc/telemt; do backup_path "$p"; done

  install_web_stack
  install_telemt
  render_telemt
  render_tproxy
  render_mtproxy_sponsor
  render_caddy
  write_caddy_env
  systemctl daemon-reload

  # Caddy initially owns :443 after the upstream installer. For FakeTLS on 443,
  # stop Caddy, apply the loopback :8443 config, then start Telemt on :443.
  if [[ $FAKETLS_PORT -eq 443 ]]; then
    systemctl stop caddy
    /usr/local/bin/caddy validate --config "$CADDY_CFG" --adapter caddyfile >/dev/null
    systemctl restart caddy
  else
    if port_in_use "$FAKETLS_PORT"; then
      local owner
      owner="$(ss -lntp | grep -E ":${FAKETLS_PORT}[[:space:]]" || true)"
      [[ -z $owner ]] || die "FakeTLS port $FAKETLS_PORT is already in use: $owner"
    fi
  fi
  systemctl enable --now telemt
  systemctl restart tproxy-server mtproxy caddy telemt
  verify_stack_ready || die "FakeTLS is not ready. See Telemt logs above. Repair using: tgproxy apply"

  save_config
  ok "Base installation completed and services verified."
  show_links

  if [[ $sponsor == 1 ]]; then
    setup_sponsor_interactive
    # Sponsor is routed through Telegram Middle-End nodes. Initializing the
    # writer pool can take significantly longer than binding the TCP listener.
    wait_for_sponsor_route || true
  fi

  echo
  if ! health_check; then
    warn "One or more health checks failed. Check service logs before sharing proxy links."
    return 1
  fi
  echo
  ok "Done. Open the manager any time with: tgproxy"
}
