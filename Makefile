.PHONY: help install test

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: test/bats/bin/bats ## Install test dependencies (bats submodules)

test/bats/bin/bats:
	git submodule init
	git submodule update

test: test/bats/bin/bats ## Run all bats unit tests
	./test/bats/bin/bats --print-output-on-failure -r test/units/
