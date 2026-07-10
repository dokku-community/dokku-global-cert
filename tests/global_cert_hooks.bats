#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  APP="$(new_app_name)"
  APP2=""
  SRC=""
}

teardown() {
  cleanup_app "$APP"
  [ -n "${APP2:-}" ] && cleanup_app "$APP2"
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  return 0
}

install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com" "DNS:global.example.com"
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
