# Contributing

Contributions are welcome through focused issues and pull requests.

1. Keep the tool read-only and compatible with Bash 4.4+.
2. Do not add telemetry, automatic blocking, configuration changes, package installation, payload capture, or secret-file reads.
3. Use synthetic fixture identities and RFC 5737 documentation addresses only.
4. Add or update parser tests for every log-format change.
5. Run `make syntax`, `make shellcheck`, and `make test`.
6. Explain compatibility and security impact in the pull request.

Avoid `eval`, unvalidated shell interpolation, predictable temporary files, and output that may expose credentials or message bodies.
