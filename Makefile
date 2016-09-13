BUSTED_ARGS ?= -v
TEST_CMD ?= bin/busted $(BUSTED_ARGS)

.PHONY: install lint test

install:
	@luarocks make

lint:
	@luacheck . \
		--std 'ngx_lua+busted' \
		--no-unused-args

test:
	@$(TEST_CMD) spec/
