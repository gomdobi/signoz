FOUNDRYCTL ?= foundryctl
KUBECTL ?= kubectl
RUBY ?= ruby

.PHONY: check-tools forge check test

check-tools:
	@$(FOUNDRYCTL) version | grep -Eq 'Version:[[:space:]]+v0\.2\.17[[:space:]]*$$' || { echo 'Foundry v0.2.17 is required for this experiment.' >&2; exit 1; }
	@$(KUBECTL) version --client >/dev/null
	@$(RUBY) -ryaml -rjson -ropen3 -e 'exit 0'

forge: check-tools
	@$(FOUNDRYCTL) --no-ledger --no-updater forge -f casting.yaml -p ./pours

check: forge
	@$(RUBY) validate.rb $(KUBECTL)

test: forge
	@$(RUBY) test_validate.rb $(KUBECTL)
