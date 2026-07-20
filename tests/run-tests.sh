#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export SMTP_EGRESS_AUDIT_LIBRARY=1
# shellcheck source=bin/smtp-egress-audit
source "$ROOT/bin/smtp-egress-audit"

PASS=0
FAIL=0
assert_eq() {
    local expected="$1" actual="$2" name="$3"
    if [[ "$actual" == "$expected" ]]; then printf 'ok - %s\n' "$name"; ((PASS+=1));
    else printf 'not ok - %s\n  expected: %q\n  actual:   %q\n' "$name" "$expected" "$actual"; ((FAIL+=1)); fi
}
assert_fails() {
    local name="$1"; shift
    if ( "$@" >/dev/null 2>&1 ); then printf 'not ok - %s\n' "$name"; ((FAIL+=1));
    else printf 'ok - %s\n' "$name"; ((PASS+=1)); fi
}

assert_eq 1 "$(count_postfix_status sent <"$ROOT/fixtures/postfix.log")" "count status=sent"
assert_eq 1 "$(count_postfix_status deferred <"$ROOT/fixtures/postfix.log")" "count status=deferred"
assert_eq 1 "$(count_postfix_status bounced <"$ROOT/fixtures/postfix.log")" "count status=bounced"
assert_eq "      1 alice@example.com" "$(extract_sasl_usernames <"$ROOT/fixtures/postfix.log")" "extract sasl_username"
assert_eq "alice@example.com 192.0.2.10 mail.example.com PLAIN" "$(extract_smtp_auth <"$ROOT/fixtures/postfix.log")" "extract SMTP username/IP/hostname"
assert_eq 14477 "$(printf 'port 14477\npermitrootlogin no\n' | parse_sshd_port)" "parse non-default SSH port"
assert_eq "deploy 192.0.2.10 publickey
admin 198.51.100.20 password" "$(extract_ssh_success <"$ROOT/fixtures/auth.log")" "extract SSH username/IP"
assert_eq "alice@example.com 192.0.2.10 imap-login
bob@example.net 198.51.100.21 pop3-login" "$(extract_dovecot_success <"$ROOT/fixtures/dovecot.log")" "extract Dovecot username/IP"
assert_eq 2 "$(postqueue_count <"$ROOT/fixtures/postqueue.txt")" "count Postfix queue"
assert_eq 0 "$(printf 'Mail queue is empty\n' | postqueue_count)" "empty Postfix queue"
assert_eq 1 "$(printf 'z1Y2x3W4v5  1234 Sun Jul 19 sender@example.com\n' | postqueue_count)" "count long Postfix queue ID"

redacted="$(redact_postconf <"$ROOT/fixtures/postconf.txt")"
assert_eq 0 "$(grep -c 'test-only-value\|sasl_passwd' <<<"$redacted" || true)" "redact Postfix secrets"
assert_eq 2 "$(grep -c 'configured\|REDACTED' <<<"$redacted")" "retain safe redaction markers"
assert_eq 'tcp dst port 587 and (tcp[tcpflags] & tcp-syn != 0)' "$(tcpdump_filter 587)" "tcpdump BPF filter"
assert_fails "reject invalid tcpdump port" tcpdump_filter '25;id'
assert_fails "reject invalid environment port" env -u SMTP_EGRESS_AUDIT_LIBRARY SMTP_PORT='25;id' "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject leading-zero environment port" env -u SMTP_EGRESS_AUDIT_LIBRARY SMTP_PORT=025 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject invalid resolver flag" env -u SMTP_EGRESS_AUDIT_LIBRARY RESOLVE_HOSTNAMES=maybe "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject zero sample interval" env -u SMTP_EGRESS_AUDIT_LIBRARY SAMPLE_INTERVAL=0 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject negative active threshold" env -u SMTP_EGRESS_AUDIT_LIBRARY ACTIVE_THRESHOLD=-1 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject leading-zero active threshold" env -u SMTP_EGRESS_AUDIT_LIBRARY ACTIVE_THRESHOLD=08 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject unsafe interface" env -u SMTP_EGRESS_AUDIT_LIBRARY INTERFACE='eth0;id' "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject relative log root" env -u SMTP_EGRESS_AUDIT_LIBRARY LOG_ROOT=relative "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject root as log root" env -u SMTP_EGRESS_AUDIT_LIBRARY LOG_ROOT=/ "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject extra CLI arguments" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" report extra
assert_fails "reject zero watch duration" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" watch 0
assert_fails "reject leading-zero watch duration" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" watch 08
assert_fails "reject unknown command" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" unknown
assert_fails "interactive mode refuses non-TTY input" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" interactive
assert_fails "interactive command rejects extra arguments" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" interactive extra
assert_fails "no-argument non-TTY invocation remains non-interactive" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit"
cli_tmp="$(mktemp -d)"
set +e
cli_output="$(env -u SMTP_EGRESS_AUDIT_LIBRARY LOG_ROOT="$cli_tmp/reports" "$ROOT/bin/smtp-egress-audit" interactive </dev/null 2>&1)"
cli_status=$?
set -e
assert_eq 2 "$cli_status" "non-TTY interactive exit status"
assert_eq 1 "$(grep -c 'interactive mode requires a terminal' <<<"$cli_output")" "non-TTY interactive error message"
if [[ ! -e "$cli_tmp/reports" ]]; then printf 'ok - non-TTY guard creates no report\n'; ((PASS+=1)); else printf 'not ok - non-TTY guard creates no report\n'; ((FAIL+=1)); fi
case "$cli_tmp" in /tmp/*) rm -rf -- "$cli_tmp" ;; *) printf 'Refusing unsafe test cleanup: %s\n' "$cli_tmp" >&2; exit 1 ;; esac

assert_eq 0 "$(watch_duration_for_choice s)" "skip live observation"
assert_eq 60 "$(watch_duration_for_choice 1)" "one-minute observation"
assert_eq 300 "$(watch_duration_for_choice 2)" "five-minute observation"
assert_eq 600 "$(watch_duration_for_choice '')" "default ten-minute observation"
assert_eq 1800 "$(watch_duration_for_choice 4)" "thirty-minute observation"
assert_fails "reject unsupported observation choice" watch_duration_for_choice '5;id'
assert_eq 'skipped' "$(format_duration 0)" "format skipped observation"
assert_eq '10 min' "$(format_duration 600)" "format recommended observation"
assert_eq '1 hour ago' "$(history_window_for_choice 1)" "one-hour history"
assert_eq '6 hours ago' "$(history_window_for_choice 2)" "six-hour history"
assert_eq '24 hours ago' "$(history_window_for_choice '')" "default history window"
assert_eq '7 days ago' "$(history_window_for_choice 4)" "seven-day history"
assert_fails "reject unsupported history choice" history_window_for_choice 5
assert_eq 25 "$(prompt_incident_port 2>/dev/null <<< '')" "interactive port default"
assert_eq 587 "$(prompt_incident_port 2>/dev/null <<< '587')" "interactive custom port"
assert_eq '6 hours ago' "$(prompt_history_window 2>/dev/null <<< '2')" "interactive history selection"
assert_eq 300 "$(prompt_watch_duration 2>/dev/null <<< '2')" "interactive duration selection"
cancel_port_prompt() { prompt_incident_port <<<q; }
assert_fails "interactive prompt supports cancellation" cancel_port_prompt
wizard_cancel_output="$(
    interactive_available() { return 0; }
    running_as_root() { return 0; }
    interactive_wizard 2>/dev/null <<<q
)"
assert_eq 1 "$(grep -c 'Cancelled; no report was created.' <<<"$wizard_cancel_output")" "wizard cancellation happens before collection"
wizard_tmp="$(mktemp -d)"
wizard_confirm_output="$(
    interactive_available() { return 0; }
    running_as_root() { return 0; }
    init_run() { RUN_DIR="$wizard_tmp"; mkdir -p -- "$RUN_DIR"; printf 'INIT:%s\n' "$1"; }
    check_socket_capture() { SOCKET_CAPTURE_STATUS=missing; }
    monitor_loop() { printf 'MONITOR:%s:%s\n' "$1" "$2"; CAPTURE_STATUS=missing; : >"$RUN_DIR/tcpdump-syn.log"; : >"$RUN_DIR/ss-snapshots.log"; }
    system_audit() { printf 'system details\n'; }
    run_report() { printf 'report details\n'; }
    incident_summary() { printf 'SUMMARY:%s|%s|%s\n' "$SMTP_PORT" "$SINCE" "$INCIDENT_WATCH_SECONDS"; }
    interactive_wizard 2>/dev/null <<< $'587\n2\n2\n\n'
)"
assert_eq 1 "$(grep -c 'MONITOR:300:compact' <<<"$wizard_confirm_output")" "wizard applies selected live duration"
assert_eq 1 "$(grep -c 'SUMMARY:587|6 hours ago|300' <<<"$wizard_confirm_output")" "wizard applies selected port and history"
case "$wizard_tmp" in /tmp/*) rm -rf -- "$wizard_tmp" ;; *) printf 'Refusing unsafe test cleanup: %s\n' "$wizard_tmp" >&2; exit 1 ;; esac
assert_eq 0 "$(printf 'ss: not installed\n' | count_socket_rows)" "missing ss message is not socket activity"
assert_eq 1 "$(printf 'ESTAB 0 0 192.0.2.1:40000 198.51.100.1:25 users:((\"smtp\",pid=42,fd=3))\n' | count_socket_rows)" "count valid ss connection row"

assert_eq NON_MTA_PROCESS "$(classify_incident 20 ready 20 0 2 0 0 -1)" "non-mail process has highest priority"
assert_eq RETRY_STORM "$(classify_incident 20 ready 20 20 0 2 9 50)" "MTA traffic with deferred queue evidence"
assert_eq MAIL_ACTIVITY "$(classify_incident 20 ready 20 20 0 2 9 -1)" "retry assessment requires queue evidence"
assert_eq MAIL_ACTIVITY "$(classify_incident 20 ready 20 20 0 8 0 0)" "recognized MTA traffic"
assert_eq MAIL_ACTIVITY "$(classify_incident 0 missing 0 1 0 0 0 -1)" "BPF-only MTA evidence counts as live activity"
assert_eq UNKNOWN_OWNER "$(classify_incident 20 ready 0 0 0 8 0 0)" "observed traffic without owner"
assert_eq QUIET "$(classify_incident 0 ready 0 0 0 0 0 -1)" "healthy capture with no observed traffic"
assert_eq LIMITED_VISIBILITY "$(classify_incident 0 missing 0 0 0 0 0 -1)" "missing capture is inconclusive"
assert_eq LIMITED_VISIBILITY "$(classify_incident 0 skipped 0 0 0 0 40 200)" "historical activity alone does not prove live cause"
assert_eq FULL "$(evidence_coverage ready 1 1)" "full evidence coverage"
assert_eq PARTIAL "$(evidence_coverage missing 1 1)" "partial evidence coverage"
assert_eq MINIMAL "$(evidence_coverage missing 0 0)" "minimal evidence coverage"
if is_mta_process smtp && is_mta_process postfix-smtp && ! is_mta_process python3 && ! is_mta_process master; then
    printf 'ok - classify SMTP process owners\n'; ((PASS+=1))
else
    printf 'not ok - classify SMTP process owners\n'; ((FAIL+=1))
fi

summary_tmp="$(mktemp -d)"
printf '1700000000.0 IP 192.0.2.1.40000 > 198.51.100.10.25: Flags [S]\n' >"$summary_tmp/tcpdump-syn.log"
printf 'ESTAB 0 0 192.0.2.1:40000 198.51.100.10:25 users:((\"python3\",pid=42,fd=3))\n' >"$summary_tmp/ss-snapshots.log"
: >"$summary_tmp/initial-sockets.log"
: >"$summary_tmp/tcpdump.stderr"
: >"$summary_tmp/tcpconnect-bpfcc.log"
cp "$ROOT/fixtures/postfix.log" "$summary_tmp/mail.log"
printf 'bounded\n' >"$summary_tmp/mail.log.scope"
cp "$ROOT/fixtures/postqueue.txt" "$summary_tmp/postqueue.txt"
printf 'ready\n' >"$summary_tmp/postqueue.status"
summary_output="$(
    RUN_DIR="$summary_tmp"
    CAPTURE_STATUS=started
    CAPTURE_PROCESS_SEEN=1
    SOCKET_CAPTURE_STATUS=ready
    PEAK_ACTIVE=1
    SMTP_PORT=25
    SINCE='24 hours ago'
    INCIDENT_WATCH_SECONDS=60
    incident_summary
)"
assert_eq 1 "$(grep -c 'Assessment: NON-MAIL PROCESS NEEDS ATTENTION' <<<"$summary_output")" "render high-attention incident assessment"
assert_eq 1 "$(grep -c 'Private evidence directory:' <<<"$summary_output")" "render private evidence location"
assert_eq 1 "$(grep -c 'no firewall, service, queue, account, or mail configuration was changed' <<<"$summary_output")" "render read-only safety reminder"
printf 'ESTAB 0 0 192.0.2.1:40000 198.51.100.10:25 users:((\"smtp\",pid=43,fd=3))\n' >"$summary_tmp/ss-snapshots.log"
grep 'status=deferred' "$ROOT/fixtures/postfix.log" >"$summary_tmp/mail.log"
printf 'unbounded-file\n' >"$summary_tmp/mail.log.scope"
printf 'failed\n' >"$summary_tmp/postqueue.status"
unbounded_output="$(
    RUN_DIR="$summary_tmp"
    CAPTURE_STATUS=started
    CAPTURE_PROCESS_SEEN=1
    SOCKET_CAPTURE_STATUS=ready
    PEAK_ACTIVE=1
    SMTP_PORT=25
    SINCE='1 hour ago'
    INCIDENT_WATCH_SECONDS=60
    incident_summary
)"
assert_eq 1 "$(grep -c 'Assessment: MAIL TRAFFIC OBSERVED' <<<"$unbounded_output")" "unbounded fallback cannot trigger retry assessment"
assert_eq 1 "$(grep -c 'queue=unavailable | log-scope=unbounded-file' <<<"$unbounded_output")" "failed queue and unbounded logs stay explicit"
case "$summary_tmp" in /tmp/*) rm -rf -- "$summary_tmp" ;; *) printf 'Refusing unsafe test cleanup: %s\n' "$summary_tmp" >&2; exit 1 ;; esac

help_output="$(env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" --help)"
assert_eq 1 "$(grep -c 'smtp-egress-audit interactive' <<<"$help_output")" "help advertises interactive mode"
assert_eq 'smtp-egress-audit 1.2.0' "$(env -u SMTP_EGRESS_AUDIT_LIBRARY PATH=/usr/bin:/bin "$ROOT/bin/smtp-egress-audit" --version)" "works without optional utilities"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
