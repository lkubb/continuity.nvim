## help: Print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

## all: Generate docs, lint, and run tests
.PHONY: all
all: doc lint test

## doc: Generate documentation. Requires pandoc and emmylua_doc_cli in PATH.
.PHONY: doc
doc: venv
	@echo "• Rendering markdown docs"
	@venv/bin/emmylua-render --no-expand '*InitOptsWithMeta' --format md --out README.md templates/continuity.md.jinja
	@echo "• Rendering vim docs"
	@venv/bin/emmylua-render --no-expand '*InitOptsWithMeta' --format vim --out doc/continuity.txt templates/continuity.txt.jinja

## test: Run tests. If `FILE` env var is specified, searches for a matching file in `tests`. Substrings are allowed (e.g. `FILE=layout` finds tests/core/test_layout.lua).
.PHONY: test
test: deps _cleantest
	@if [ -n "$(FILE)" ]; then \
		FILE_NO_EXT="$$(echo "$(FILE)" | sed 's/\.lua$$//')"; \
		if [ -f "tests/$$FILE_NO_EXT.lua" ]; then \
			FOUND_FILE="tests/$$FILE_NO_EXT.lua"; \
		elif [ -f "$$FILE_NO_EXT.lua" ]; then \
			FOUND_FILE="$$FILE_NO_EXT.lua"; \
		else \
			FOUND_FILE="$$(find tests -path "*$$FILE_NO_EXT*.lua" -type f | head -1)"; \
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
.test/env: .test/env/cache .test/env/config .test/env/data .test/env/state .test/env/run
.test/env/cache:
	@mkdir -p ".test/env/cache"
.test/env/config:
	@mkdir -p ".test/env/config"
.test/env/data:
	@mkdir -p ".test/env/data"
.test/env/state:
	@mkdir -p ".test/env/state"
.test/env/run:
	@mkdir -p ".test/env/run"

## deps: Install all library dependencies
deps: deps/gitsigns.nvim deps/luv deps/mini.nvim deps/neogit deps/oil.nvim

deps/gitsigns.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/lewis6991/gitsigns.nvim $@

deps/luv:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/LuaCATS/luv $@

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@

deps/neogit:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/NeogitOrg/neogit $@

deps/oil.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/stevearc/oil.nvim $@

## lint: Run linters, test-render md/vim docs and EmmyLuaLS typechecking
.PHONY: lint
lint: fastlint
	@echo "• Static analysis with emmylua_check"
	@VIMRUNTIME=$$(nvim -es '+put=$$VIMRUNTIME|print|quit!') \
		emmylua_check --warnings-as-errors -c .emmyrc.json lua tests
	@echo "• Checking vim doc template"
	@venv/bin/emmylua-render --format vim templates/continuity.txt.jinja >/dev/null

## fastlint: Run only fast linters test-render md docs
.PHONY: fastlint
fastlint: deps venv
	@echo "• Checking markdown doc template"
	@venv/bin/emmylua-render --format md templates/continuity.md.jinja > /dev/null # todo: markdownlint?
	@echo "• Basic static analysis with luacheck"
	@luacheck lua tests --formatter plain
	@echo "• Checking formatting"
	@stylua --check lua tests

venv:
	@echo "• Creating venv"
	python3 -m venv venv
	@echo "• Installing emmylua-render into venv"
	venv/bin/pip install git+https://github.com/lkubb/emmylua-render

## clean: Reset the repository to a clean state
.PHONY: clean
clean:
	rm -rf .test deps venv
