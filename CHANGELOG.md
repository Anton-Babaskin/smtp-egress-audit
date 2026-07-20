# Changelog

All notable changes to this project are documented here.

## [1.2.0] - 2026-07-20

### Added

- Guided `interactive` provider-alert investigation with automatic TTY startup when no command is supplied.
- Compact three-stage progress, private detailed evidence files, and a cautious incident assessment.
- Explicit capture quality and evidence coverage reporting so unavailable tooling is never presented as zero activity.
- Process attribution from both `ss` snapshots and optional `tcpconnect-bpfcc` output.

### Changed

- Monitoring now preserves a summary after Ctrl+C instead of dropping collected evidence during an interrupted sleep.
- Postfix queue counting accepts long alphanumeric queue IDs.
- Numeric settings and watch durations reject ambiguous leading-zero values instead of reaching Bash octal arithmetic.
- Traditional log fallback and queue-command failures are identified explicitly and cannot create a time-window retry assessment.
- Version bumped to 1.2.0; English and Russian usage documentation now lead with the interactive workflow.

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
