#!/usr/bin/env bats

load 'test_helper'

# The uninstall trigger is fired against a sandboxed DOKKU_LIB_ROOT so the real
# plugin install is never disturbed by the test run.

teardown() {
  cleanup_sandboxes
}

@test "(uninstall) removes the config root for the global-cert plugin" {
  local sandbox
  sandbox="$(sandbox_lib_root)"
  $SUDO mkdir -p "${sandbox}/config/global-cert"
  $SUDO touch "${sandbox}/config/global-cert/server.crt"

  run fire_trigger "LIB_ROOT=${sandbox}" uninstall global-cert
  [ "$status" -eq 0 ]

  $SUDO test ! -d "${sandbox}/config/global-cert"
}

@test "(uninstall) leaves the config root intact for another plugin" {
  local sandbox
  sandbox="$(sandbox_lib_root)"
  $SUDO mkdir -p "${sandbox}/config/global-cert"
  $SUDO touch "${sandbox}/config/global-cert/server.crt"

  run fire_trigger "LIB_ROOT=${sandbox}" uninstall some-other-plugin
  [ "$status" -eq 0 ]

  $SUDO test -d "${sandbox}/config/global-cert"
}
