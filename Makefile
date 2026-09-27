# Tarantool used by `test-under` (and therefore by `test-ee`).
TARANTOOL    ?= tarantool
TARANTOOL_EE ?= /Users/blikh/data/workspace/sdk/3.7.0-r137/tarantool

ROCKS    := $(CURDIR)/.rocks
LUACHECK := $(ROCKS)/bin/luacheck
LUATEST  := $(ROCKS)/bin/luatest

# The tt-generated .rocks/bin/luatest is a shell wrapper that execs a hard-coded
# tarantool binary, so it cannot be pointed at another one. To run the suite
# under a specific tarantool, call luatest's Lua entry point directly and hand
# it the rocks tree through LUA_PATH/LUA_CPATH, which is what the wrapper does
# for its own interpreter.
LUATEST_LUA     := $(ROCKS)/share/tarantool/rocks/luatest/scm-1/bin/luatest
ROCKS_LUA_PATH  := $(ROCKS)/share/tarantool/?.lua;$(ROCKS)/share/tarantool/?/init.lua;;
ROCKS_LUA_CPATH := $(ROCKS)/lib/tarantool/?.so;;

# luatest wipes its VARDIR (default /tmp/t, shared by every luatest on the
# host) at startup, so two checkouts running the suite at once delete each
# other's files. Keep it private to this checkout, keyed by a checksum of the
# path so that it stays short.
export VARDIR ?= /tmp/tarantool-avro-t/$(firstword $(shell printf '%s' '$(CURDIR)' | cksum))

.PHONY: deps lint test test-under test-ee

deps:
	tt rocks install luatest
	tt rocks install luacheck

lint:
	$(LUACHECK) .

test:
	$(LUATEST) -v test/

# Runs the suite under $(TARANTOOL) instead of the one baked into the wrapper.
test-under:
	LUA_PATH='$(ROCKS_LUA_PATH)' LUA_CPATH='$(ROCKS_LUA_CPATH)' \
		$(TARANTOOL) $(LUATEST_LUA) -v test/

test-ee:
	$(MAKE) test-under TARANTOOL=$(TARANTOOL_EE)
