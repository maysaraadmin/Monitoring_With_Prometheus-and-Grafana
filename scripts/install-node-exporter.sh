#!/usr/bin/env bash
# Install node-exporter on a Linux VPS, bound to one address only.
#
# Run this ON the VPS, as root:
#   curl -fsSL <raw-url>/scripts/install-node-exporter.sh -o install-node-exporter.sh
#   less install-node-exporter.sh          # read it before running it as root
#   bash install-node-exporter.sh 100.x.y.z
#
# The argument is the address node-exporter listens on. It is NOT optional, on
# purpose: the default would be 0.0.0.0, which publishes your kernel version,
# filesystems, interfaces and uptime to the whole internet, unauthenticated.
# Port 9100 is indexed by internet-wide scanners. See docs/Security_issues.md S7.1.
#
# Pass the private address Prometheus will reach this host on -- the Tailscale
# or WireGuard IP, or 127.0.0.1 if you are using an SSH tunnel.
set -euo pipefail

BIND_ADDR="${1:-}"
VERSION="${NODE_EXPORTER_VERSION:-}"

if [ -z "$BIND_ADDR" ]; then
  echo "usage: $0 <bind-address>    e.g. $0 100.101.102.103  (or 127.0.0.1 for an SSH tunnel)" >&2
  echo "refusing to default to 0.0.0.0 -- see the comment at the top of this script" >&2
  exit 2
fi

if [ "$BIND_ADDR" = "0.0.0.0" ] || [ "$BIND_ADDR" = "::" ]; then
  echo "refusing to bind to $BIND_ADDR: that exposes this host's metrics to the internet." >&2
  echo "if you really want this, edit the unit file by hand afterwards and accept S7.1." >&2
  exit 2
fi

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  armv7l)  ARCH=armv7 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Resolve the latest release unless pinned. Pin it in production (see F4.2):
#   NODE_EXPORTER_VERSION=1.8.2 bash install-node-exporter.sh <addr>
if [ -z "$VERSION" ]; then
  echo "resolving latest node_exporter release..."
  VERSION="$(curl -fsSL https://api.github.com/repos/prometheus/node_exporter/releases/latest \
             | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$VERSION" ] || { echo "could not resolve the latest version; set NODE_EXPORTER_VERSION" >&2; exit 1; }
fi
echo "installing node_exporter ${VERSION} (${ARCH}), listening on ${BIND_ADDR}:9100"

TARBALL="node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
BASE="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

curl -fsSL -o "$TARBALL" "${BASE}/${TARBALL}"
curl -fsSL -o sha256sums.txt "${BASE}/sha256sums.txt"

# Verify before running anything we just downloaded as root. Do not remove this.
grep " ${TARBALL}\$" sha256sums.txt > expected.txt \
  || { echo "no checksum published for ${TARBALL}" >&2; exit 1; }
sha256sum -c expected.txt
echo "checksum OK"

tar xzf "$TARBALL"
install -m 0755 "node_exporter-${VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/node_exporter

id -u node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

cat > /etc/systemd/system/node_exporter.service <<UNIT
[Unit]
Description=Prometheus node exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
# Bound to one address on purpose. 0.0.0.0 here is a security finding (S7.1).
ExecStart=/usr/local/bin/node_exporter \\
  --web.listen-address=${BIND_ADDR}:9100 \\
  --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)(\$|/)'
Restart=on-failure
RestartSec=5
# Hardening: it only needs to read /proc and /sys.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
LockPersonality=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now node_exporter

# Prove it came up bound where we asked, rather than assuming (AC7.2.1).
sleep 2
if command -v ss >/dev/null 2>&1; then
  echo "--- listener ---"
  ss -tlnp 2>/dev/null | grep ':9100' || { echo "node_exporter is not listening on 9100" >&2; exit 1; }
  if ss -tln 2>/dev/null | grep -qE '(0\.0\.0\.0|\[::\]):9100'; then
    echo "WARNING: 9100 appears bound to a wildcard address. This is S7.1. Check the unit file." >&2
    exit 1
  fi
fi

curl -fsS "http://${BIND_ADDR}:9100/metrics" >/dev/null \
  && echo "OK: node_exporter ${VERSION} is serving metrics on ${BIND_ADDR}:9100"

cat <<NEXT

Done. Next, on the monitoring host, add this server to
prometheus/targets/vps.yml:

  - targets: ['${BIND_ADDR}:9100']
    labels:
      instance: '<a-name-you-will-recognise>'
      role: 'web'

then: docker compose restart prometheus

Still to check yourself (this script cannot): that 9100 is NOT reachable
from the public internet. From an unrelated machine, run
  curl -m 5 http://<this-vps-public-ip>:9100/metrics
and confirm it is refused. That is test T7.S1.
NEXT
