## help: Print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

## all: Generate docs, lint, and run tests
.PHONY: all
all: doc lint test

venv:
	python3 -m venv venv
	venv/bin/pip install -r scripts/requirements.txt

## doc: Generate documentation
.PHONY: doc
doc: scripts/nvim_doc_tools
	python scripts/main.py generate
	python scripts/main.py lint

## test: Run tests. If `FILE` env var is specified, searches for a matching file in `tests`. Substrings are allowed (e.g. `FILE=layout` finds tests/core/test_layout.lua).
.PHONY: test
test: deps _cleantest
	@if [ -n "$(FILE)" ]; then \
		FILE_NO_EXT=$$(echo "$(FILE)" | sed 's/\.lua$$//'); \
		if [ -f "tests/$$FILE_NO_EXT.lua" ]; then \
			FOUND_FILE="tests/$$FILE_NO_EXT.lua"; \
		elif [ -f "$$FILE_NO_EXT.lua" ]; then \
			FOUND_FILE="$$FILE_NO_EXT.lua"; \
		else \
			FOUND_FILE=$$(find tests -path "*$$FILE_NO_EXT*.lua" -type f | head -1); \
		fi; \
		if [ -z "$$FOUND_FILE" ]; then \
			echo "Error: No test file matching '$(FILE)' found in tests/"; \
			exit 1; \
		fi; \
		echo "Running tests in: $$FOUND_FILE"; \
		XDG_CONFIG_HOME=".test/env/config" \
		XDG_DATA_HOME=".test/env/data" \
		XDG_STATE_HOME=".test/env/state" \
		XDG_RUNTIME_DIR=".test/env/run" \
		XDG_CACHE_HOME=".test/env/cache" \
		nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$$FOUND_FILE')"; \
	else \
		XDG_CONFIG_HOME=".test/env/config" \
		XDG_DATA_HOME=".test/env/data" \
		XDG_STATE_HOME=".test/env/state" \
		XDG_RUNTIME_DIR=".test/env/run" \
		XDG_CACHE_HOME=".test/env/cache" \
		nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"; \
	fi;

.PHONY: _cleantest
_cleantest: .test
	@rm -rf ".test/env/state/nvim"; \
	rm -f ".test/nvim_init.lua"

.test: .test/env
.test/env: .test/env/config .test/env/data .test/env/state .test/env/run .test/env/cache
.test/env/config:
	@mkdir -p ".test/env/config"
.test/env/data:
	@mkdir -p ".test/env/data"
.test/env/state:
	@mkdir -p ".test/env/state"
.test/env/run:
	@mkdir -p ".test/env/run"
.test/env/cache:
	@mkdir -p ".test/env/cache"

## deps: Install all library dependencies
deps: deps/mini.nvim

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@

## lint: Run linters and LuaLS typechecking
.PHONY: lint
lint: scripts/nvim-typecheck-action fastlint
	./scripts/nvim-typecheck-action/typecheck.sh --workdir scripts/nvim-typecheck-action lua

## fastlint: Run only fast linters
.PHONY: fastlint
fastlint: scripts/nvim_doc_tools
	python scripts/main.py lint
	luacheck lua tests --formatter plain
	stylua --check lua tests

scripts/nvim_doc_tools:
	git clone https://github.com/stevearc/nvim_doc_tools scripts/nvim_doc_tools

scripts/nvim-typecheck-action:
	git clone https://github.com/stevearc/nvim-typecheck-action scripts/nvim-typecheck-action

## clean: Reset the repository to a clean state
.PHONY: clean
clean:
	rm -rf scripts/nvim_doc_tools scripts/nvim-typecheck-action
