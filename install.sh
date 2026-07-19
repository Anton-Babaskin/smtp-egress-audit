#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: run install.sh as root" >&2; exit 1; }

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENABLE_MONITOR=0
FORCE_CONFIG=0

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh [--enable-monitor] [--force-config]

  --enable-monitor  enable and start continuous monitoring
  --force-config    replace /etc/default/smtp-egress-audit
EOF
}

while (( $# )); do
    case "$1" in
        --enable-monitor) ENABLE_MONITOR=1 ;;
        --force-config) FORCE_CONFIG=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

install -D -m 0755 "$ROOT_DIR/bin/smtp-egress-audit" /usr/local/sbin/smtp-egress-audit
if [[ ! -e /etc/default/smtp-egress-audit || $FORCE_CONFIG -eq 1 ]]; then
    install -D -m 0600 "$ROOT_DIR/config/smtp-egress-audit.default" /etc/default/smtp-egress-audit
else
    echo "Keeping existing /etc/default/smtp-egress-audit (use --force-config to replace it)."
fi
install -D -m 0644 "$ROOT_DIR/systemd/smtp-egress-audit-monitor.service" /etc/systemd/system/smtp-egress-audit-monitor.service
install -D -m 0644 "$ROOT_DIR/systemd/smtp-egress-audit-report.service" /etc/systemd/system/smtp-egress-audit-report.service
install -D -m 0644 "$ROOT_DIR/systemd/smtp-egress-audit-report.timer" /etc/systemd/system/smtp-egress-audit-report.timer
install -D -m 0644 "$ROOT_DIR/logrotate/smtp-egress-audit" /etc/logrotate.d/smtp-egress-audit
install -d -m 0700 -o root -g root /var/log/smtp-egress-audit

systemctl daemon-reload
if (( ENABLE_MONITOR )); then
    systemctl enable --now smtp-egress-audit-monitor.service
    echo "Continuous monitor enabled."
else
    echo "Continuous monitor was not started. Use --enable-monitor or enable it later with systemctl."
fi
echo "Installed smtp-egress-audit $(/usr/local/sbin/smtp-egress-audit --version | awk '{print $2}')"
