#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  APP="$(new_app_name)"
  SRC=""
}

teardown() {
  cleanup_app "$APP"
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  return 0
}

install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com" "DNS:global.example.com"
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

@test "(global-cert:remove) leaves apps that use the global cert with a working copy" {
  install_fixture_cert
  create_app "$APP"
  $SUDO test -f "$(app_tls_crt "$APP")"

  run dokku global-cert:remove
  [ "$status" -eq 0 ]

  # the app keeps its own copy of the certificate
  $SUDO test -f "$(app_tls_crt "$APP")"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]

  # the global cert itself is gone
  $SUDO test ! -f "$(global_cert_crt)"
  $SUDO test ! -f "$(global_cert_key)"
}

@test "(global-cert:remove) fails when no global cert is defined" {
  run dokku global-cert:remove
  [ "$status" -ne 0 ]
  [[ "$output" == *"A global SSL endpoint is not defined"* ]]
}

@test "(global-cert:remove) leaves a generated csr in place" {
  gc_generate
  $SUDO test -f "$(global_cert_csr)"

  run dokku global-cert:remove
  [ "$status" -eq 0 ]

  # remove deletes only the crt/key endpoint; the csr from generate remains
  $SUDO test ! -f "$(global_cert_crt)"
  $SUDO test ! -f "$(global_cert_key)"
  $SUDO test -f "$(global_cert_csr)"

  run dokku global-cert:show csr
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN CERTIFICATE REQUEST"* ]]
}
