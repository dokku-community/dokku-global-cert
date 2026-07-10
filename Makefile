DOKKU_VERSION ?= latest
GCTEST_HOST_DIR ?= $(CURDIR)/tmp/gctest-host

# Optional path or filename relative to /plugin-src/tests passed to bats, e.g.
# `make unit-tests UNIT_TESTS=global_cert_report.bats`. Defaults to the whole
# tests directory.
UNIT_TESTS ?= .
# Optional regex passed to bats --filter to scope down to a single test name.
UNIT_TESTS_FILTER ?=
BATS_FLAGS := --timing --print-output-on-failure
ifneq ($(UNIT_TESTS_FILTER),)
BATS_FLAGS += --filter '$(UNIT_TESTS_FILTER)'
endif

COMPOSE := DOKKU_VERSION=$(DOKKU_VERSION) GCTEST_HOST_DIR=$(GCTEST_HOST_DIR) docker compose -f tests/docker-compose.yml
COMPOSE_COMPOSE_MODE := $(COMPOSE) --profile compose-mode
COMPOSE_EXEC_DOKKU := $(COMPOSE) exec -T dokku

PLUGIN_BASH_FILES := commands config help-functions install internal-functions \
	post-app-clone post-create uninstall \
	$(wildcard subcommands/*) \
	tests/setup.sh tests/setup-native.sh tests/test_helper.bash

.PHONY: setup build-stack wait-stack install-plugin test lint unit-tests clean logs \
	setup-native unit-tests-native clean-native

setup: build-stack wait-stack install-plugin

build-stack:
	mkdir -p $(GCTEST_HOST_DIR)
	$(COMPOSE_COMPOSE_MODE) build
	$(COMPOSE_COMPOSE_MODE) up -d

wait-stack:
	$(COMPOSE_COMPOSE_MODE) up -d --wait

install-plugin:
	$(COMPOSE_EXEC_DOKKU) bash /plugin-src/tests/setup.sh

lint:
	$(COMPOSE_EXEC_DOKKU) shellcheck $(addprefix /plugin-src/, $(PLUGIN_BASH_FILES))

unit-tests:
	$(COMPOSE_EXEC_DOKKU) bats $(BATS_FLAGS) /plugin-src/tests/$(UNIT_TESTS)

test: lint unit-tests

logs:
	$(COMPOSE) logs --no-color --tail=200

clean:
	$(COMPOSE_COMPOSE_MODE) down -v --remove-orphans
	# The host-side state dir contains files owned by root inside the
	# dokku container, which the host user cannot rm without elevation.
	rm -rf $(GCTEST_HOST_DIR) 2>/dev/null || sudo rm -rf $(GCTEST_HOST_DIR)

# --- Native mode: dokku installed on the host. global-cert needs no supporting services. ---

setup-native:
	bash tests/setup-native.sh

unit-tests-native:
	SUDO=sudo bats $(BATS_FLAGS) tests/$(UNIT_TESTS)

clean-native:
	@echo "global-cert needs no supporting compose services; nothing to tear down"
