#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${TGPROXYFORGE_REPO:-https://github.com/Net-spoof/TGProxyForge.git}"
BRANCH="${TGPROXYFORGE_BRANCH:-main}"
TARGET_DIR="/usr/local/lib/tgproxyforge"
LINK="/usr/local/bin/tgproxy"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[TGProxyForge] Run as root: sudo -i" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates
fi

if [[ -e "$TARGET_DIR" ]]; then
  BACKUP="${TARGET_DIR}.before-bootstrap-$(date +%Y%m%d-%H%M%S)"
  echo "[TGProxyForge] Moving previous source to $BACKUP"
  mv "$TARGET_DIR" "$BACKUP"
fi

echo "[TGProxyForge] Cloning $REPO ($BRANCH)..."
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TARGET_DIR"
chmod +x "$TARGET_DIR/tgproxy" "$TARGET_DIR/install.sh"
ln -sfn "$TARGET_DIR/tgproxy" "$LINK"

echo "[TGProxyForge] Manager installed: $LINK"
exec "$LINK" install
