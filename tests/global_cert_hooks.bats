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
# to call more than once per test; the prior fixture dir is removed first. Any
# arguments after <cn> are forwarded to `global-cert:set` (e.g. --force).
install_fixture_cert() {
  local cn="${1:-global.example.com}"; shift || true
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "$cn" "DNS:${cn}"
  dokku global-cert:set "$@" "${SRC}/server.crt" "${SRC}/server.key"
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

@test "(global-cert:set) applies the global cert to a pre-existing app without a certificate" {
  # the app exists before any global cert is set, so it starts without a cert
  create_app "$APP"
  $SUDO test ! -f "$(app_tls_crt "$APP")"

  # setting the global cert now applies it to the pre-existing app
  install_fixture_cert
  $SUDO test -f "$(app_tls_crt "$APP")"
  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:set) leaves a pre-existing app with its own certificate untouched" {
  create_app "$APP"

  # give the app its own certificate before any global cert exists
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  # setting the global cert for the first time must not clobber the app's own cert
  install_fixture_cert

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"own.example.com"* ]]
  [[ "$output" != *"global.example.com"* ]]
}

@test "(global-cert:set --force) replaces an app-specific certificate on every app" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own certificate
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  # --force reapplies the global cert to every app, replacing the app-specific one
  install_fixture_cert "updated.example.com" --force

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated.example.com"* ]]
  [[ "$output" != *"own.example.com"* ]]
}

@test "(dokku --force global-cert:set) replaces an app-specific certificate on every app" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own certificate
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  # the global --force flag is stripped by the cli before the subcommand sees it,
  # so this exercises the DOKKU_APPS_FORCE_DELETE path
  rm -rf "$SRC"
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "forced.example.com" "DNS:forced.example.com"
  run dokku --force global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
  [ "$status" -eq 0 ]

  run dokku certs:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"forced.example.com"* ]]
  [[ "$output" != *"own.example.com"* ]]
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
