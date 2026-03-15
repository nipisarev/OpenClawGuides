.PHONY: help install test lint validate

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## Run the install script
	bash src/install.sh

test: ## Run all test scripts in src/tests/
	@for f in src/tests/*.sh; do echo "--- $$f ---"; bash "$$f"; done

lint: ## Run shellcheck on all .sh files in src/
	find src -name '*.sh' -exec shellcheck {} +

validate: ## Run config validation tests
	bash src/tests/test-configs.sh
