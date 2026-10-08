fake_link() {
  # Auto-hostname users connect directly to the server IP; the generated SNI
  # hostname is still encoded in the ee FakeTLS secret.
  local host="$DOMAIN"
  [[ ${AUTO_DOMAIN:-0} == 1 ]] && host="$SERVER_IP"
  printf 'tg://proxy?server=%s&port=%s&secret=ee%s%s\n' "$host" "$FAKETLS_PORT" "$BASE_SECRET" "$(hex_text "$DOMAIN")"
}

web_link() {
  printf 'tg://webproxy?server=%s&secret=dd%s\n' "$DOMAIN" "$BASE_SECRET"
}

web_https_link() {
  printf 'https://t.me/webproxy?server=%s&secret=dd%s\n' "$DOMAIN" "$BASE_SECRET"
}

show_links() {
  load_config
  hr
  printf "%bFakeTLS MTProto%b\n%s\n\n" "$C_BOLD" "$C_RESET" "$(fake_link)"
  printf "%bTelegram WEB Proxy%b\n%s\n%s\n" "$C_BOLD" "$C_RESET" "$(web_link)" "$(web_https_link)"
  hr
}

service_state() {
  local s=$1
  systemctl is-active --quiet "$s" 2>/dev/null && printf '%bactive%b' "$C_GREEN" "$C_RESET" || printf '%binactive%b' "$C_RED" "$C_RESET"
}

show_status() {
  load_config
  hr
  printf "%b%s %s%b\n" "$C_BOLD" "$APP_NAME" "$APP_VERSION" "$C_RESET"
  printf "Domain          : %s\n" "$DOMAIN"
  printf "Domain mode     : %s\n" "$([[ ${AUTO_DOMAIN:-0} == 1 ]] && echo 'auto / sslip.io' || echo 'custom')"
  printf "Server IP       : %s\n" "$SERVER_IP"
  printf "FakeTLS port    : %s\n" "$FAKETLS_PORT"
  printf "Sponsor         : %s\n" "$([[ $SPONSOR_ENABLED == 1 ]] && echo enabled || echo disabled)"
  [[ $SPONSOR_ENABLED == 1 ]] && printf "Sponsor tag     : %s\n" "$ADTAG"
  printf "Telemt          : "; service_state telemt; echo
  printf "tproxy-server   : "; service_state tproxy-server; echo
  printf "Official MTProxy: "; service_state mtproxy; echo
  printf "Caddy           : "; service_state caddy; echo
  echo
  ss -lntp 2>/dev/null | grep -E ":(${FAKETLS_PORT}|443|8443|${RELAY_PORT}|${ADMIN_PORT}|2398|9091)[[:space:]]" || true
  hr
}

test_tcp() {
  local host=$1 port=$2 timeout_s=${3:-4}
  timeout "$timeout_s" bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

sponsor_diagnostics() {
  load_config
  hr
  echo "Sponsor / Middle Proxy diagnostics"
  printf "Configured: %s\n" "$([[ $SPONSOR_ENABLED == 1 ]] && echo yes || echo no)"
  if [[ $SPONSOR_ENABLED != 1 ]]; then warn "Sponsor is disabled."; hr; return 0; fi
  printf "Tag       : %s\n\n" "$ADTAG"

  local pq=35.180.139.74
  if test_tcp "$pq" 8888 4; then ok "Generic outbound TCP/8888 is reachable."
  else warn "Outbound TCP/8888 appears blocked. Sponsor promotion may not be displayed."; fi

  if curl -fsS --max-time 3 http://127.0.0.1:9091/v1/runtime/gates >/tmp/tgpf-gates.json 2>/dev/null; then
    jq '.data | {accepting_new_connections,use_middle_proxy,me_runtime_ready,route_mode,reroute_active,reroute_reason,startup_stage}' /tmp/tgpf-gates.json
  else
    warn "Telemt API is not reachable on 127.0.0.1:9091."
  fi
  hr
}

# During the first boot, Telemt can temporarily use direct fallback while its
# Telegram Middle-End writer pool initializes. Poll only in the installation
# wizard, not during ordinary 'tgproxy health' calls.
wait_for_sponsor_route() {
  load_config
  [[ $SPONSOR_ENABLED == 1 ]] || return 0

  local i
  log "Waiting up to 180 seconds for Telegram Middle Proxy sponsor routing..."
  for i in $(seq 1 36); do
    if curl -fsS --max-time 3 http://127.0.0.1:9091/v1/runtime/gates 2>/dev/null |
       jq -e '.data.me_runtime_ready == true and .data.use_middle_proxy == true and .data.route_mode == "middle" and .data.reroute_active == false' >/dev/null; then
      ok "Telegram Middle Proxy routing is ready."
      return 0
    fi
    sleep 5
  done

  warn "Telegram Middle Proxy is not yet ready. The proxy may still work in direct mode, but the sponsored channel may not appear."
  return 1
}

health_check() {
  load_config
  local failures=0 code
  hr
  echo "Health check"
  printf "DNS A          : "; resolve_domain_ip "$DOMAIN" || true; echo
  printf "HTTPS          : "
  code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 12 "https://$DOMAIN/" 2>/dev/null)" || code="FAIL"
  printf '%s\n' "$code"
  [[ $code == 200 ]] || failures=$((failures+1))

  printf "WEB healthz    : "
  if curl -fsS --max-time 3 "http://127.0.0.1:${ADMIN_PORT}/healthz"; then echo
  else echo FAIL; failures=$((failures+1)); fi

  printf "WEB readyz     : "
  if curl -fsS --max-time 3 "http://127.0.0.1:${ADMIN_PORT}/readyz"; then echo
  else echo FAIL; failures=$((failures+1)); fi

  printf "Telemt service : "
  if systemctl is-active --quiet telemt && telemt_has_listener; then echo "LISTENING :$FAKETLS_PORT"
  else echo FAIL; failures=$((failures+1)); fi

  printf "Telemt API     : "
  if curl -fsS --max-time 3 http://127.0.0.1:9091/v1/users >/dev/null 2>&1; then echo OK
  else echo FAIL; failures=$((failures+1)); fi

  printf "Generic :8888  : "
  if test_tcp 35.180.139.74 8888 4; then echo OPEN; else echo BLOCKED/TIMEOUT; fi

  sponsor_diagnostics
  if [[ $SPONSOR_ENABLED == 1 ]]; then
    if curl -fsS --max-time 3 http://127.0.0.1:9091/v1/runtime/gates \
        2>/dev/null | jq -e '.data.me_runtime_ready == true and .data.route_mode == "middle" and .data.reroute_active == false' >/dev/null; then
      ok "Sponsor: Telegram Middle Proxy route is active."
    else
      warn "Sponsor is configured, but the real Middle Proxy route is not ready; promotion may not appear."
      failures=$((failures+1))
    fi
  fi

  if (( failures > 0 )); then
    warn "Health check failed ($failures checks). Installation is not fully ready."
    return 1
  fi
  ok "All required health checks passed."
}

setup_sponsor_interactive() {
  load_config
  echo
  echo "Telegram sponsor setup (@MTProxyBot)"
  echo "1) Open @MTProxyBot and send /newproxy"
  echo "2) Send: ${SERVER_IP}:${FAKETLS_PORT}"
  echo "3) When asked for secret, send this BASE secret (not the ee link):"
  echo "   ${BASE_SECRET}"
  echo "4) Copy the 32-hex Proxy Tag returned by the bot."
  echo
  local tag
  while true; do
    read -r -p "Proxy Tag (32 hex, or blank to configure later): " tag
    tag=${tag,,}
    if [[ -z $tag ]]; then
      SPONSOR_ENABLED=0; ADTAG=''; save_config; return 0
    fi
    valid_adtag "$tag" && break
    warn "Tag must be exactly 32 hexadecimal characters."
  done
  ADTAG="$tag"; SPONSOR_ENABLED=1; save_config
  apply_config
  ok "Sponsor tag applied. In @MTProxyBot use /myproxies -> Set promotion and choose a public channel."
  warn "Telegram may take up to about one hour to show the promotion. Telemt also needs working outbound access to Telegram Middle-End servers (commonly TCP/8888)."
}
