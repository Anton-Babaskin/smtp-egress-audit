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

redacted="$(redact_postconf <"$ROOT/fixtures/postconf.txt")"
assert_eq 0 "$(grep -c 'test-only-value\|sasl_passwd' <<<"$redacted" || true)" "redact Postfix secrets"
assert_eq 2 "$(grep -c 'configured\|REDACTED' <<<"$redacted")" "retain safe redaction markers"
assert_eq 'tcp dst port 587 and (tcp[tcpflags] & tcp-syn != 0)' "$(tcpdump_filter 587)" "tcpdump BPF filter"
assert_fails "reject invalid tcpdump port" tcpdump_filter '25;id'
assert_fails "reject invalid environment port" env -u SMTP_EGRESS_AUDIT_LIBRARY SMTP_PORT='25;id' "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject invalid resolver flag" env -u SMTP_EGRESS_AUDIT_LIBRARY RESOLVE_HOSTNAMES=maybe "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject zero sample interval" env -u SMTP_EGRESS_AUDIT_LIBRARY SAMPLE_INTERVAL=0 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject negative active threshold" env -u SMTP_EGRESS_AUDIT_LIBRARY ACTIVE_THRESHOLD=-1 "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject unsafe interface" env -u SMTP_EGRESS_AUDIT_LIBRARY INTERFACE='eth0;id' "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject relative log root" env -u SMTP_EGRESS_AUDIT_LIBRARY LOG_ROOT=relative "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject root as log root" env -u SMTP_EGRESS_AUDIT_LIBRARY LOG_ROOT=/ "$ROOT/bin/smtp-egress-audit" --version
assert_fails "reject extra CLI arguments" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" report extra
assert_fails "reject zero watch duration" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" watch 0
assert_fails "reject unknown command" env -u SMTP_EGRESS_AUDIT_LIBRARY "$ROOT/bin/smtp-egress-audit" unknown
assert_eq 'smtp-egress-audit 1.1.0' "$(env -u SMTP_EGRESS_AUDIT_LIBRARY PATH=/usr/bin:/bin "$ROOT/bin/smtp-egress-audit" --version)" "works without optional utilities"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
