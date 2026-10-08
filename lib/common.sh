APP_NAME="TGProxyForge"
APP_VERSION="0.1.0"
REPO="Net-spoof/TGProxyForge"
APP_DIR="/opt/tgproxyforge"
SRC_DIR="$APP_DIR/src"
SITE_DIR="$APP_DIR/site"
BACKUP_DIR="$APP_DIR/backups"
STATE_DIR="/etc/tgproxyforge"
CONFIG_FILE="$STATE_DIR/config.env"
TELEMT_CFG="/etc/telemt/telemt.toml"
TELEMT_BIN="/usr/local/bin/telemt"
TELEMT_UNIT="/etc/systemd/system/telemt.service"
TPROXY_CFG="/etc/tproxy-server/config.json"
TPROXY_PROFILES="/etc/tproxy-server/profiles.json"
CADDY_CFG="/etc/caddy/Caddyfile"
MTPROXY_ENV="/etc/mtproxy/mtproxy.env"
MTPROXY_OVERRIDE="/etc/systemd/system/mtproxy.service.d/tgproxyforge.conf"
TELEMT_VERSION="3.5.13"
TELEMT_AMD64_SHA256="92021ad31520302bfbfe4a13b49adc9d129ec48a08699f81515e9c55668be9fa"
TPROXY_COMMIT="c8adb8b7c6b7fc46c12ae3acb68be9070c26a8e8"

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'

log()  { printf "%b[%s]%b %s\n" "$C_BLUE" "$APP_NAME" "$C_RESET" "$*"; }
ok()   { printf "%b✔%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b⚠%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf "%b✘%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
hr()   { printf '%s\n' '────────────────────────────────────────────────────────────'; }

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this command as root (sudo -i)."
}

is_ipv4() {
  local ip=$1 IFS=.
  local -a o
  [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  read -r -a o <<<"$ip"
  [[ ${#o[@]} -eq 4 ]] || return 1
  local n
  for n in "${o[@]}"; do (( n >= 0 && n <= 255 )) || return 1; done
}

is_domain() {
  local d=${1,,}
  [[ $d =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && $d == *.* ]]
}

valid_port() {
  [[ ${1:-} =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

valid_secret() { [[ ${1:-} =~ ^[0-9a-f]{32}$ ]]; }
valid_adtag()  { [[ ${1:-} =~ ^[0-9a-fA-F]{32}$ ]]; }

prompt_yes_no() {
  local prompt=$1 default=${2:-y} ans
  local hint='[Y/n]'; [[ $default == n ]] && hint='[y/N]'
  while true; do
    read -r -p "$prompt $hint: " ans || true
    ans=${ans,,}
    [[ -z $ans ]] && ans=$default
    case $ans in y|yes) return 0;; n|no) return 1;; esac
    echo "Please enter y or n."
  done
}

random_secret() { openssl rand -hex 16; }

hex_text() {
  LC_ALL=C printf '%s' "$1" | od -An -tx1 -v | tr -d ' \n'
}

detect_public_ip() {
  local candidate
  for u in https://api.ipify.org https://ifconfig.co/ip https://icanhazip.com; do
    candidate="$(curl -4fsSL --connect-timeout 5 --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_ipv4 "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

resolve_domain_ip() {
  getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}'
}

port_in_use() {
  ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$1$"
}

choose_loopback_port() {
  local p=$1
  while port_in_use "$p"; do ((p++)); done
  printf '%s\n' "$p"
}

backup_path() {
  local p=$1
  [[ -e $p ]] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$p" "$BACKUP_DIR/$(basename "$p").$(date +%Y%m%d-%H%M%S).bak"
}

save_config() {
  mkdir -p "$STATE_DIR"
  cat >"$CONFIG_FILE" <<EOF_CFG
DOMAIN=$(printf '%q' "$DOMAIN")
SERVER_IP=$(printf '%q' "$SERVER_IP")
FAKETLS_PORT=$(printf '%q' "$FAKETLS_PORT")
BASE_SECRET=$(printf '%q' "$BASE_SECRET")
SPONSOR_ENABLED=$(printf '%q' "$SPONSOR_ENABLED")
ADTAG=$(printf '%q' "$ADTAG")
ACME_EMAIL=$(printf '%q' "$ACME_EMAIL")
RELAY_PORT=$(printf '%q' "$RELAY_PORT")
ADMIN_PORT=$(printf '%q' "$ADMIN_PORT")
EOF_CFG
  chmod 600 "$CONFIG_FILE"
}

load_config() {
  [[ -f $CONFIG_FILE ]] || die "No TGProxyForge installation found. Run: tgproxy install"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
}

install_prereqs() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git jq openssl coreutils iproute2 dnsutils tcpdump nftables python3 tar gzip >/dev/null
}
