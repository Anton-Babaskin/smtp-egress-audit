#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: run uninstall.sh as root" >&2; exit 1; }
PURGE_LOGS=0
[[ ${1:-} == "--purge-logs" ]] && { PURGE_LOGS=1; shift; }
(( $# == 0 )) || { echo "Usage: sudo ./uninstall.sh [--purge-logs]" >&2; exit 2; }

systemctl disable --now smtp-egress-audit-monitor.service smtp-egress-audit-report.timer 2>/dev/null || true
systemctl stop smtp-egress-audit-report.service 2>/dev/null || true
rm -f -- \
    /usr/local/sbin/smtp-egress-audit \
    /etc/default/smtp-egress-audit \
    /etc/systemd/system/smtp-egress-audit-monitor.service \
    /etc/systemd/system/smtp-egress-audit-report.service \
    /etc/systemd/system/smtp-egress-audit-report.timer \
    /etc/logrotate.d/smtp-egress-audit
systemctl daemon-reload
if (( PURGE_LOGS )); then
    [[ -d /var/log/smtp-egress-audit ]] && rm -rf -- /var/log/smtp-egress-audit
    echo "Removed program, configuration, units, and accumulated reports."
else
    echo "Removed program, configuration, and units. Reports remain in /var/log/smtp-egress-audit."
fi
