# Changelog

All notable changes to this project are documented here.

## [1.1.0] - 2026-07-19

### Added

- Initial open-source release.
- One-shot system audit and historical Postfix/authentication reports.
- Bounded and continuous outbound SMTP SYN monitoring.
- `ss` process/PID snapshots and optional `tcpconnect-bpfcc` integration.
- Postfix queue, delivery, relay, SMTP auth, SSH, Dovecot, Fail2ban, container, cron, timer, and conntrack reporting.
- Strict environment/argument validation, secret redaction, private per-run reports, systemd/logrotate integration, synthetic tests, and CI.
- Reliable fallback to traditional mail/auth logs when journald contains only service lifecycle records.
- Detection of the effective non-default SSH port for established-session reporting.
