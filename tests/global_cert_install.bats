#!/usr/bin/env bats

load 'test_helper'

teardown() {
  cleanup_sandboxes
}

@test "(install) the plugin config root exists after installation" {
  # `make setup` runs `dokku plugin:install`, which fires the install trigger.
  $SUDO test -d "$(global_cert_root)"
}

@test "(install) the install trigger creates the config root" {
  local sandbox
  sandbox="$(sandbox_lib_root)"
  $SUDO test ! -d "${sandbox}/config/global-cert"

  run fire_trigger "LIB_ROOT=${sandbox}" install
  [ "$status" -eq 0 ]

  $SUDO test -d "${sandbox}/config/global-cert"
}

@test "(install) the install trigger is idempotent" {
  local sandbox
  sandbox="$(sandbox_lib_root)"
  fire_trigger "LIB_ROOT=${sandbox}" install
  run fire_trigger "LIB_ROOT=${sandbox}" install
  [ "$status" -eq 0 ]
  $SUDO test -d "${sandbox}/config/global-cert"
}
