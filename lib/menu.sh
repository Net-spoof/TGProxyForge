edit_domain_ip() {
  load_config
  local d ip dns_ip
  read -r -p "New domain [$DOMAIN]: " d; d=${d:-$DOMAIN}; d=${d,,}
  is_domain "$d" || { warn "Invalid domain."; return 1; }
  read -r -p "New public IPv4 [$SERVER_IP]: " ip; ip=${ip:-$SERVER_IP}
  is_ipv4 "$ip" || { warn "Invalid IPv4."; return 1; }
  dns_ip="$(resolve_domain_ip "$d")"
  [[ $dns_ip == "$ip" ]] || warn "DNS currently resolves to '${dns_ip:-nothing}', not $ip."
  DOMAIN="$d"; SERVER_IP="$ip"
  save_config; apply_config; ok "Domain/IP updated. Existing FakeTLS links using the old domain are now stale."
}

edit_port() {
  load_config
  local p
  while true; do
    read -r -p "New FakeTLS port [$FAKETLS_PORT]: " p; p=${p:-$FAKETLS_PORT}
    valid_port "$p" || { warn "Invalid port."; continue; }
    [[ $p -ne 80 ]] || { warn "Port 80 is reserved."; continue; }
    break
  done
  FAKETLS_PORT="$p"; save_config; apply_config; ok "FakeTLS port updated."
}

edit_sponsor() {
  load_config
  echo "1) Enable/change sponsor tag"
  echo "2) Disable sponsor"
  echo "3) Diagnostics"
  echo "0) Back"
  local n tag
  read -r -p "Choice: " n
  case $n in
    1)
      echo "Register ${SERVER_IP}:${FAKETLS_PORT} with @MTProxyBot using base secret:"
      echo "$BASE_SECRET"
      while true; do
        read -r -p "32-hex Proxy Tag: " tag; tag=${tag,,}
        valid_adtag "$tag" && break
        warn "Invalid tag."
      done
      SPONSOR_ENABLED=1; ADTAG="$tag"; save_config; apply_config; sponsor_diagnostics;;
    2)
      prompt_yes_no "Disable sponsor?" n || return 0
      SPONSOR_ENABLED=0; ADTAG=''; save_config; apply_config; ok "Sponsor disabled.";;
    3) sponsor_diagnostics;;
    0) return 0;;
    *) warn "Unknown choice.";;
  esac
}

regenerate_secret() {
  load_config
  warn "This invalidates BOTH current FakeTLS and WEB proxy links."
  prompt_yes_no "Generate a new secret?" n || return 0
  BASE_SECRET="$(random_secret)"
  # A Telegram promotion tag is registered against the secret; force re-registration.
  SPONSOR_ENABLED=0; ADTAG=''
  save_config; apply_config
  ok "Secret rotated. Sponsor was disabled; register the new secret with @MTProxyBot again if needed."
  show_links
}

restart_all() {
  systemctl restart telemt tproxy-server mtproxy caddy
  ok "Services restarted."
}

self_update() {
  [[ -d ${SCRIPT_ROOT:-}/.git ]] || die "This installation is not backed by a Git checkout. Re-run the bootstrap installer."
  git -C "$SCRIPT_ROOT" fetch --quiet --depth 1 origin main
  git -C "$SCRIPT_ROOT" reset --quiet --hard origin/main
  chmod +x "$SCRIPT_ROOT/tgproxy"
  ln -sfn "$SCRIPT_ROOT/tgproxy" /usr/local/bin/tgproxy
  ok "TGProxyForge updated from GitHub. Re-run: tgproxy"
}
uninstall_menu() {
  warn "This removes TGProxyForge services/configuration. Backups under $BACKUP_DIR are kept."
  prompt_yes_no "Continue uninstall?" n || return 0
  systemctl disable --now telemt tproxy-server mtproxy caddy tproxy-firewall refresh-mtproxy-config.timer 2>/dev/null || true
  rm -f "$TELEMT_UNIT" "$MTPROXY_OVERRIDE" /usr/local/bin/tgproxy /usr/local/sbin/tgproxyforge
  if [[ -n ${SCRIPT_ROOT:-} && $SCRIPT_ROOT == /usr/local/lib/tgproxyforge ]]; then
    rm -rf /usr/local/lib/tgproxyforge
  fi
  systemctl daemon-reload
  warn "Binaries/configs from upstream components were intentionally left in place for manual recovery."
}

menu() {
  need_root
  load_config
  while true; do
    clear || true
    printf "%b%s v%s%b\n" "$C_BOLD$C_CYAN" "$APP_NAME" "$APP_VERSION" "$C_RESET"
    printf "Domain: %s  |  FakeTLS: %s  |  Sponsor: %s\n" "$DOMAIN" "$FAKETLS_PORT" "$([[ $SPONSOR_ENABLED == 1 ]] && echo ON || echo OFF)"
    hr
    cat <<'EOF_MENU'
1) Status
2) Show proxy links
3) Edit domain / public IP
4) Change FakeTLS port
5) Sponsor settings
6) Rotate proxy secret
7) Restart all services
8) Health & TCP/8888 diagnostics
9) Re-apply current configuration
10) Update TGProxyForge from GitHub
11) Uninstall / disable stack
0) Exit
EOF_MENU
    hr
    local c
    read -r -p "Select: " c
    case $c in
      1) show_status;; 2) show_links;; 3) edit_domain_ip;; 4) edit_port;; 5) edit_sponsor;;
      6) regenerate_secret;; 7) restart_all;; 8) health_check;; 9) apply_config; ok "Configuration re-applied.";;
      10) self_update; return 0;; 11) uninstall_menu; return 0;; 0) return 0;; *) warn "Invalid choice.";;
    esac
    echo; read -r -p "Press Enter to continue..." _ || true
    load_config
  done
}

usage() {
  cat <<EOF_USAGE
$APP_NAME v$APP_VERSION
Usage:
  tgproxy              Open interactive management menu
  tgproxy install      Install both proxy stacks
  tgproxy status       Show status
  tgproxy links        Show generated links
  tgproxy health       Run diagnostics
  tgproxy apply        Re-apply saved configuration
  tgproxy update       Update manager from GitHub
EOF_USAGE
}

main() {
  case ${1:-menu} in
    install) wizard;; menu) menu;; status) need_root; show_status;; links) need_root; show_links;;
    health) need_root; health_check;; apply) need_root; apply_config;; update) need_root; self_update;;
    -h|--help|help) usage;; *) usage; exit 2;;
  esac
}
