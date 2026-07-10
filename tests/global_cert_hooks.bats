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

# Install a global cert whose CN/SAN is <cn> (default global.example.com). Safe
# to call more than once per test; the prior fixture dir is removed first.
install_fixture_cert() {
  local cn="${1:-global.example.com}"
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "$cn" "DNS:${cn}"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

@test "(post-create) applies the global cert to a newly created app" {
  install_fixture_cert
  create_app "$APP"
  $SUDO test -f "$(app_tls_crt "$APP")"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(post-create) leaves a new app without certs when no global cert is set" {
  create_app "$APP"
  $SUDO test ! -f "$(app_tls_crt "$APP")"
}

@test "(post-app-clone) applies the global cert to a cloned app" {
  # create the source app before the global cert exists, so the clone gets the
  # cert via post-app-clone rather than inheriting it from the source.
  create_app "$APP"
  $SUDO test ! -f "$(app_tls_crt "$APP")"

  install_fixture_cert
  APP2="$(new_app_name)"
  dokku apps:clone --skip-deploy "$APP" "$APP2"
  $SUDO test -f "$(app_tls_crt "$APP2")"
}

@test "(global-cert:set) re-applies an updated global cert to apps that use it" {
  install_fixture_cert
  create_app "$APP"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]

  # updating the global cert propagates to the app that is using it
  install_fixture_cert "updated.example.com"

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated.example.com"* ]]
}

@test "(global-cert:set) leaves an app with its own certificate untouched" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own, independent certificate
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  # updating the global cert must not overwrite the app's own certificate
  install_fixture_cert "updated.example.com"

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"own.example.com"* ]]
  [[ "$output" != *"updated.example.com"* ]]
}

@test "(post-create) fails when fired without an app" {
  run fire_trigger post-create
  [ "$status" -ne 0 ]
  [[ "$output" == *"Please specify an app to run the command on"* ]]
}

@test "(post-app-clone) fails when fired without an app" {
  run fire_trigger post-app-clone
  [ "$status" -ne 0 ]
  [[ "$output" == *"Please specify an app to run the command on"* ]]
}
