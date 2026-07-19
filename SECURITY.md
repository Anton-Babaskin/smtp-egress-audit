# Security policy

## Reporting a vulnerability

Please use GitHub's private security advisory feature for this repository. Do not open a public issue containing exploit details, credentials, private mail metadata, or server logs.

## Security boundaries

`smtp-egress-audit` is a local, read-only evidence collector. Root execution exposes sensitive operational metadata, so report directories use `umask 077`, directory mode `0700`, and file mode `0600`. Treat every report as confidential.

The project intentionally does not read Postfix password databases, capture payloads, change firewall/MTA/SSH settings, block IPs, or install packages. PTR lookups are the only optional network lookup and can be disabled.

Supported security fixes target the latest released version.
