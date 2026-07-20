# smtp-egress-audit

## Quick Start

Provider reported excessive outbound TCP/25 connections? Install and start the guided read-only investigation:

```bash
git clone https://github.com/Anton-Babaskin/smtp-egress-audit.git
cd smtp-egress-audit
sudo ./install.sh
sudo smtp-egress-audit
```

The assistant asks for the port, log window, and observation time, then prints a compact assessment and the private evidence directory. It does not block addresses, stop services, or change mail configuration.

`smtp-egress-audit` is a read-only Bash tool for investigating abnormal outbound SMTP connection alerts on Linux servers. It correlates outbound TCP SYN metadata, active sockets and owning processes, Postfix delivery records, authenticated mail users, SSH/Dovecot logins, queues, services, scheduled jobs, containers, and relevant configuration.

The tool never changes firewall, Postfix, SSH, or Fail2ban configuration; never blocks an address; and never captures packet payloads or message bodies.

Version: **1.2.0** · License: MIT · [Русская документация](docs/README.ru.md)

## Supported systems and requirements

- Ubuntu 22.04/24.04 and current Debian releases
- Postfix systems, including Mail-in-a-Box
- Bash 4.4+, standard GNU userland
- Root is recommended for complete journals, process attribution, `tcpdump`, conntrack, and service data
- Core runtime: `bash`, `awk`, `sed`, `grep`, `sort`, `ss`, `journalctl`
- Optional: `tcpdump`, `tcpconnect-bpfcc`, `conntrack`, `postqueue`, `postconf`, `fail2ban-client`, Docker, Podman, `getent`, `timeout`

Missing optional commands are reported as `not installed` or `unavailable`; they do not abort the audit. The installer does not install packages.

## Installation

```bash
git clone https://github.com/Anton-Babaskin/smtp-egress-audit.git
cd smtp-egress-audit
sudo ./install.sh
```

The installer places the executable in `/usr/local/sbin`, configuration in `/etc/default/smtp-egress-audit`, systemd units in `/etc/systemd/system`, logrotate policy in `/etc/logrotate.d`, and creates `/var/log/smtp-egress-audit` with mode `0700`. An existing configuration is preserved; `--force-config` explicitly replaces it.

Continuous monitoring is not started automatically. To opt in during installation:

```bash
sudo ./install.sh --enable-monitor
```

## Interactive provider-alert assistant

For the common case where a hosting provider reports unusually many outbound connections to TCP/25, run the guided assistant:

```bash
sudo smtp-egress-audit
# or explicitly:
sudo smtp-egress-audit interactive
```

The interactive assistant requires root so it can read journals and attribute packets and PIDs completely. It asks only for the destination SMTP port, historical log window, and bounded live-observation time. It then:

1. starts preserving volatile socket and SYN metadata;
2. collects system, Postfix, queue, authentication, job, and container context;
3. prints a compact, cautious assessment and the private report location.

The assessment distinguishes recognized mail traffic, possible Postfix retry activity, a non-mail process that needs attention, traffic without process attribution, an event not reproduced during a healthy capture, and incomplete evidence. It never labels a server “safe” merely because no connection appeared during a short observation.

If journald has no relevant records and the tool falls back to a traditional log file, the summary labels that source `unbounded-file`. Those counts remain visible for context but are not used to claim retry activity for the selected time window.

Detailed output stays in private files below the run directory instead of overwhelming the terminal. Choosing to skip live capture still preserves an immediate socket snapshot. Ctrl+C ends the live observation early and continues building the report. The wizard remains read-only and requires a real terminal; automation and systemd should continue using the explicit commands below.

## Commands

```bash
sudo smtp-egress-audit audit
sudo smtp-egress-audit report
sudo smtp-egress-audit watch 3600
sudo smtp-egress-audit monitor
sudo SINCE="7 days ago" smtp-egress-audit report
sudo SMTP_PORT=587 smtp-egress-audit watch 600
```

- `interactive`: guided, compact investigation of a provider SMTP alert; also starts automatically with no arguments in a terminal.
- `audit`: full one-time system and historical-log audit.
- `report`: historical Postfix, SSH, SMTP authentication, IMAP, and POP3 report.
- `watch [seconds]`: bounded observation, default 600 seconds, maximum 7 days.
- `monitor`: continuous observation until SIGTERM or Ctrl+C.

Every run creates a timestamped, private directory below `LOG_ROOT`. `report.txt` contains the console report; raw files stored there contain only the log/socket metadata used by the report.

## Configuration

Defaults can be overridden in the environment or `/etc/default/smtp-egress-audit` for systemd:

```text
LOG_ROOT=/var/log/smtp-egress-audit
SMTP_PORT=25
SINCE="24 hours ago"
SAMPLE_INTERVAL=1
ACTIVE_THRESHOLD=10
INTERFACE=auto
RESOLVE_HOSTNAMES=1
```

`SMTP_PORT` accepts 1–65535, allowing direct SMTP (`25`), implicit TLS (`465`), Submission (`587`), and common external relay port `2525`. `INTERFACE=auto` uses the default-route interface; `INTERFACE=any` is supported. PTR resolution uses a short timeout and can be disabled with `RESOLVE_HOSTNAMES=0`.

## Network evidence

The monitor uses the exact BPF expression:

```text
tcp dst port PORT and (tcp[tcpflags] & tcp-syn != 0)
```

When supported, `tcpdump -Q out` enforces outbound direction. It stores decoded header metadata only—never `-X`, `-A`, packet payload dumps, or PCAP files. Regular `ss -Htanp` snapshots preserve process/PID evidence. If installed, `tcpconnect-bpfcc` provides supplemental process attribution. The summary counts SYN attempts and groups destination IP:port and process names. An active-socket count above `ACTIVE_THRESHOLD` generates a warning.

Examples:

```bash
# Observe direct-to-MX delivery on TCP/25
sudo SMTP_PORT=25 smtp-egress-audit watch 3600

# Observe an authenticated relay on Submission or alternate relay port
sudo SMTP_PORT=587 smtp-egress-audit watch 600
sudo SMTP_PORT=2525 smtp-egress-audit watch 600
```

An external relay on 587/2525 can be healthy while the provider's TCP/25 alert concerns direct delivery. Run separate observations for each relevant destination port.

## Reading Postfix results

- `NOQUEUE: reject` and `Relay access denied` normally mean an inbound client was rejected before Postfix accepted a message. They do **not** prove successful outbound spam.
- `postfix/smtp ... status=sent` confirms a completed outbound delivery attempt accepted by the next hop.
- `status=deferred` remains queued for retry; `status=bounced` failed permanently.
- `sasl_username` identifies the mail account that authenticated to the SMTP server. Correlate it with queue ID, client IP, time, and recipient-domain volume.
- The outbound `relay=` field shows the next hop actually used.

Sensitive `postconf -n` values—especially password maps—are replaced with `configured` or `[REDACTED]`. The tool never reads `/etc/postfix/sasl_passwd`.

## Postfix and Mail-in-a-Box

Mail-in-a-Box uses Postfix and Dovecot, so the same report applies. Run `audit` as root and correlate:

1. provider alert timestamps and port;
2. SYN destinations and `ss` process/PID;
3. `postfix/smtp` delivery queue IDs and `status=`;
4. `sasl_username`, client hostname/IP, and Dovecot login activity;
5. queue size, unexpected containers/processes, cron jobs, and timers.

Do not change Mail-in-a-Box generated Postfix configuration from this tool. Investigate and remediate through the platform's supported workflow after preserving evidence.

## systemd

```bash
# Daily historical report
sudo systemctl enable --now smtp-egress-audit-report.timer
systemctl list-timers smtp-egress-audit-report.timer

# Continuous monitor (explicit opt-in)
sudo systemctl enable --now smtp-egress-audit-monitor.service
sudo systemctl status smtp-egress-audit-monitor.service

# Stop it safely
sudo systemctl disable --now smtp-egress-audit-monitor.service
```

SIGINT/SIGTERM stops child capture processes and writes a final summary.

## Provider-alert workflow

1. Record the provider's source IP, destination port, count, timezone, and exact interval.
2. Run `sudo smtp-egress-audit audit` immediately to preserve volatile state.
3. Run a bounded watch on the reported port during the suspected period.
4. Compare provider counts with SYN counts; one delivery may produce retries, so connections are not identical to messages.
5. Confirm whether owning processes are Postfix, a web application, a container, another MTA, or an unknown binary.
6. Correlate Postfix queue IDs, `status=sent`, recipient domains, relay endpoints, and authenticated accounts.
7. Distinguish rejected inbound relay probes from accepted/queued and delivered outbound mail.
8. Inspect SSH, Dovecot, SMTP authentication, sudo/su, cron/timers, containers, and Fail2ban evidence.
9. Preserve the private report before remediation; rotate compromised credentials and isolate confirmed malicious workloads through your incident-response process.

See the detailed [provider alert runbook](docs/provider-alert-runbook.md).

## Important limitations

- A reboot destroys active sockets, process state, and some counters. Historical logs and the provider's timestamped evidence therefore matter.
- Log rotation or journald retention may remove older evidence. File fallback cannot perfectly implement arbitrary `SINCE` filtering.
- NAT, namespaces, encrypted application traffic, external relays, or short-lived connections may limit attribution.
- PTR names are hints, not identity proof.
- This is an evidence-collection aid, not malware detection or a substitute for incident response.

## Development

```bash
make syntax
make shellcheck
make test
make check
```

Fixtures contain synthetic documentation-only addresses. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Uninstall

```bash
sudo ./uninstall.sh
```

Reports are preserved. Remove them only with the explicit destructive option:

```bash
sudo ./uninstall.sh --purge-logs
```
