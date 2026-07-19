SHELL := /bin/bash

.PHONY: all syntax shellcheck test check
all: check

syntax:
	@find . \( -type f -name '*.sh' -o -path './bin/smtp-egress-audit' \) | sort | xargs -r -n1 bash -n

shellcheck:
	@command -v shellcheck >/dev/null || { echo 'shellcheck: not installed' >&2; exit 127; }
	@shellcheck bin/smtp-egress-audit install.sh uninstall.sh tests/run-tests.sh

test:
	@bash tests/run-tests.sh

check: syntax shellcheck test
