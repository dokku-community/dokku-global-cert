#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  SRC=""
}

teardown() {
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  return 0
}

install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

@test "(global-cert:remove) removes an installed global cert" {
  install_fixture_cert
  run global_cert_enabled
  [ "$output" = "true" ]

  run dokku global-cert:remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing global SSL endpoint"* ]]

  $SUDO test ! -f "$(global_cert_crt)"
  $SUDO test ! -f "$(global_cert_key)"
  run global_cert_enabled
  [ "$output" = "false" ]
}

@test "(global-cert:remove) fails when no global cert is defined" {
  run dokku global-cert:remove
  [ "$status" -ne 0 ]
  [[ "$output" == *"A global SSL endpoint is not defined"* ]]
}
