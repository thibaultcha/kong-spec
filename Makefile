lint:
	@luacheck . \
		--std 'ngx_lua+busted' \
		--no-unused-args
