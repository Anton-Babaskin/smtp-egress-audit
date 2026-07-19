# Provider SMTP alert runbook

Use this runbook when a hosting provider reports unusually many outbound connections to an SMTP destination port.

## 1. Preserve the provider evidence

Ask for and record the affected server source IP, destination port, first/last timestamp with timezone, connection count, sample destinations, and whether the provider counted SYN packets, established sessions, or firewall flows. Do not assume that a TCP/25 warning concerns your configured relay on 587 or 2525.

## 2. Preserve volatile host evidence

```bash
sudo smtp-egress-audit audit
sudo smtp-egress-audit watch 3600
```

For another reported port:

```bash
sudo SMTP_PORT=587 smtp-egress-audit watch 600
```

Copy the timestamped report directory to your protected incident storage. A reboot removes active sockets and processes and may truncate useful counters.

## 3. Classify the network owner

Review SYN destination counts, `ss-snapshots.log`, and optional `tcpconnect-bpfcc.log`.

- Expected Postfix processes: correlate with queue IDs and delivery logs.
- Web runtime: inspect the application, deployment history, web access logs, and credentials.
- Container: map PID/cgroup to the container and inspect its image and entrypoint.
- Exim/Sendmail or unknown binary: determine whether it is authorized before containment.
- No local evidence: confirm time synchronization, port, provider sampling point, NAT, and whether the event preceded a reboot.

## 4. Distinguish inbound noise from outbound delivery

`NOQUEUE: reject` and `Relay access denied` normally mean the inbound SMTP server refused an unauthorised relay attempt. They are not a sent message. `postfix/smtp ... status=sent` is outbound delivery evidence. `sasl_username` connects an authenticated submission to an account; a queue ID connects stages of the same message.

## 5. Test hypotheses

- Compromised account: unusual `sasl_username`, client IP/PTR, time, destinations, or volume.
- Open relay: verify Postfix restrictions safely from an authorized external test host; never weaken restrictions to test. A rejected relay probe is evidence against that individual attempt succeeding.
- Compromised web application: web process owns outbound sockets or submits high local queue volume without SMTP auth.
- Container: container process owns sockets or submits through localhost.
- Authorized bulk mail or retry storm: known process/account with expected recipients; high deferred/retry count may amplify connections.
- Provider error: timestamps, source address, or destination port do not match preserved evidence. Request flow samples.

## 6. Respond without destroying evidence

Follow your incident process. Depending on confirmed scope, isolate the workload, rotate the affected mail/application credentials, revoke sessions/keys, patch the entry point, inspect persistence, and restore from a trusted baseline. Do not treat reinstalling as a substitute for determining how credentials or the application were compromised.

## 7. Reply to the provider

Report only necessary metadata: whether traffic was expected, observed time window, destination port, approximate connection rate, owning authorized service, and remediation status. Never send credentials, message bodies, or the unredacted configuration.
