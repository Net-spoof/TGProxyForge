# Optional, explicit one-time upgrade of existing WEB relay binaries.
# Sourced from tgproxy; does not run or change services during tgproxy update.
enable_web_ip_metrics() {
  need_root
  load_config
  local checkout="$SRC_DIR/tproxy-server" binary="/usr/local/bin/tproxy-server"
  local patcher="$SCRIPT_ROOT/lib/patch_tproxy_metrics.py"
  local go_binary="" next_binary="" prev_binary="" i

  if curl -fsS --max-time 3 "http://127.0.0.1:$ADMIN_PORT/metrics" 2>/dev/null |
       grep -Eq '^tproxy_unique_client_ips_live [0-9]+$'; then
    ok "WEB unique active IP monitoring is already enabled; no restart needed."
    return 0
  fi
  [[ -f "$checkout/internal/session/manager.go" && -f "$checkout/internal/server/server.go" ]] ||
    { warn "Pinned WEB relay source checkout is missing. No changes applied."; return 1; }
  [[ -f "$patcher" && -x "$binary" ]] ||
    { warn "Patch helper or WEB relay binary is missing. No changes applied."; return 1; }

  if [[ -x /opt/go1.26.5/bin/go ]]; then
    go_binary="/opt/go1.26.5/bin/go"
  elif command -v go >/dev/null 2>&1; then
    go_binary="$(command -v go)"
  else
    warn "Go compiler is not installed. No changes applied."
    return 1
  fi
  warn "WEB proxy sessions will be briefly interrupted when its relay restarts."
  prompt_yes_no "Rebuild WEB relay with anonymous active-IP metric?" n || return 0

  # Validate, test and build BEFORE touching the running binary.
  python3 "$patcher" "$checkout" || return 1
  next_binary="$(mktemp /usr/local/bin/.tproxyforge-next.XXXXXXXX)"
  prev_binary="$(mktemp /usr/local/bin/.tproxyforge-prev.XXXXXXXX)"
  if ! (cd "$checkout" && "$go_binary" test ./internal/session ./internal/server &&
         "$go_binary" build -trimpath -ldflags='-s -w' -o "$next_binary" ./cmd/tproxy-server); then
    rm -f "$next_binary" "$prev_binary"
    warn "WEB relay build/test failed; running proxy is unchanged."
    return 1
  fi
  chmod 0755 "$next_binary"
  cp -a "$binary" "$prev_binary"
  backup_path "$binary"
  mv -f "$next_binary" "$binary"

  if systemctl restart tproxy-server; then
    for i in $(seq 1 20); do
      if systemctl is-active --quiet tproxy-server &&
         curl -fsS --max-time 2 "http://127.0.0.1:$ADMIN_PORT/metrics" 2>/dev/null |
           grep -Eq '^tproxy_unique_client_ips_live [0-9]+$'; then
        rm -f "$prev_binary"
        ok "WEB unique active IP monitoring enabled. FakeTLS was not restarted."
        return 0
      fi
      sleep 1
    done
  fi

  warn "New WEB relay did not become ready. Restoring previous binary..."
  mv -f "$prev_binary" "$binary"
  systemctl restart tproxy-server || true
  warn "WEB relay was rolled back. Inspect: systemctl status tproxy-server"
  return 1
}
