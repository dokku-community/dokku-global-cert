#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  APP="$(new_app_name)"
  APP2=""
  SRC=""
  OWN=""
}

teardown() {
  cleanup_app "$APP"
  [ -n "${APP2:-}" ] && cleanup_app "$APP2"
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  [ -n "${OWN:-}" ] && rm -rf "$OWN"
  return 0
}

# Install a global cert whose CN/SAN is <cn> (default global.example.com). The
# prior fixture dir is removed first so it is safe to call more than once.
install_fixture_cert() {
  local cn="${1:-global.example.com}"
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "$cn" "DNS:${cn}"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

@test "(global-cert:apply) applies the global cert to an app without a certificate" {
  install_fixture_cert
  # create the app before the global cert exists so it starts without a cert
  create_app "$APP"

  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]
  $SUDO test -f "$(app_tls_crt "$APP")"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:apply) overwrites an app's own certificate with the global cert" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own, independent certificate
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
  [[ "$output" != *"own.example.com"* ]]
}

@test "(global-cert:apply) applies the global cert to multiple apps at once" {
  install_fixture_cert
  create_app "$APP"
  APP2="$(new_app_name)"
  create_app "$APP2"

  run dokku global-cert:apply "$APP" "$APP2"
  [ "$status" -eq 0 ]

  $SUDO test -f "$(app_tls_crt "$APP")"
  $SUDO test -f "$(app_tls_crt "$APP2")"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
  run dokku certs:report "$APP2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:apply) fails when no global cert is set" {
  create_app "$APP"

  run dokku global-cert:apply "$APP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"A global SSL endpoint is not defined"* ]]
}

@test "(global-cert:apply) fails when the app does not exist" {
  install_fixture_cert

  run dokku global-cert:apply "does-not-exist-$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "(global-cert:apply) fails when no app is specified" {
  install_fixture_cert

  run dokku global-cert:apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"Please specify an app to run the command on"* ]]
}

@test "(global-cert:apply) installs the exact global certificate" {
  install_fixture_cert
  create_app "$APP"

  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]
  # a fingerprint match, not just a report substring, proves the exact cert landed
  assert_app_serves_global_cert "$APP"
}

@test "(global-cert:apply) verifies every app name before applying to any" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own cert so we can tell whether a failed apply touched it
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  run dokku global-cert:apply "$APP" "does-not-exist-$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]

  # verification runs for the whole list before any apply, so the valid app is
  # left serving its own cert
  refute_app_serves_global_cert "$APP"
}

@test "(global-cert:apply) is idempotent" {
  install_fixture_cert
  create_app "$APP"

  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]
  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]
  assert_app_serves_global_cert "$APP"
}
