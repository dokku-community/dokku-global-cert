#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  APP="$(new_app_name)"
  SRC=""
  OWN=""
}

teardown() {
  cleanup_app "$APP"
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  [ -n "${OWN:-}" ] && rm -rf "$OWN"
  return 0
}

# Install a deterministic global cert (CN + two SANs) so hostname/subject/issuer
# assertions are stable.
install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com" "DNS:global.example.com,DNS:www.example.com"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

# --- global scope, no cert installed ----------------------------------------

@test "(global-cert:report) --global renders a full report" {
  run dokku global-cert:report --global
  [ "$status" -eq 0 ]
  [[ "$output" == *"global global-cert information"* ]]
  [[ "$output" == *"Global cert dir"* ]]
  [[ "$output" == *"Global cert enabled"* ]]
  [[ "$output" == *"Global cert hostnames"* ]]
  [[ "$output" == *"Global cert issuer"* ]]
  [[ "$output" == *"Global cert subject"* ]]
  [[ "$output" == *"Global cert verified"* ]]
  # applied is app-specific and must not appear in the global scope
  [[ "$output" != *"Global cert applied"* ]]
}

@test "(global-cert:report) --global-cert-enabled is false without a cert" {
  run global_cert_report_value --global-cert-enabled
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "(global-cert:report) --global-cert-dir reports the config root" {
  run global_cert_report_value --global-cert-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$(global_cert_root)" ]
}

@test "(global-cert:report) value flags are empty but succeed without a cert" {
  local flag
  for flag in --global-cert-hostnames --global-cert-issuer --global-cert-subject \
    --global-cert-expires-at --global-cert-starts-at --global-cert-verified; do
    run global_cert_report_value "$flag"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "(global-cert:report) rejects an invalid flag" {
  run dokku global-cert:report --global --not-a-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid flag passed, valid flags:"* ]]
}

@test "(global-cert:report) --format cannot be combined with an info flag" {
  run dokku global-cert:report --global --format json --global-cert-enabled
  [ "$status" -ne 0 ]
  [[ "$output" == *"--format flag cannot be specified when specifying an info flag"* ]]
}

# --- global scope, cert installed -------------------------------------------

@test "(global-cert:report) --global-cert-enabled is true with a cert" {
  install_fixture_cert
  run global_cert_report_value --global-cert-enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "(global-cert:report) --global-cert-hostnames lists the cert hostnames" {
  install_fixture_cert
  run global_cert_report_value --global-cert-hostnames
  [ "$status" -eq 0 ]
  [ "$output" = "global.example.com www.example.com" ]
}

@test "(global-cert:report) --global-cert-subject reflects the cert subject" {
  install_fixture_cert
  run global_cert_report_value --global-cert-subject
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:report) --global-cert-issuer reflects the cert issuer" {
  install_fixture_cert
  run global_cert_report_value --global-cert-issuer
  [ "$status" -eq 0 ]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:report) --global-cert-verified reports a self-signed cert" {
  install_fixture_cert
  run global_cert_report_value --global-cert-verified
  [ "$status" -eq 0 ]
  [ "$output" = "self signed" ]
}

@test "(global-cert:report) --global-cert-starts-at and --global-cert-expires-at are populated" {
  install_fixture_cert
  run global_cert_report_value --global-cert-starts-at
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run global_cert_report_value --global-cert-expires-at
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "(global-cert:report) --global full report reflects an installed cert" {
  install_fixture_cert
  run dokku global-cert:report --global
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global cert enabled"* ]]
  [[ "$output" == *"true"* ]]
  [[ "$output" == *"global.example.com"* ]]
}

# --- --format json ----------------------------------------------------------

@test "(global-cert:report) --global --format json emits a json object" {
  install_fixture_cert
  run bash -c "dokku global-cert:report --global --format json 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "true" ]
  [ "$(echo "$output" | jq -r '.dir')" = "$(global_cert_root)" ]
  [ "$(echo "$output" | jq -r '.hostnames')" = "global.example.com www.example.com" ]
  # keys are stripped of the --global-cert- prefix; applied is app-specific
  [ "$(echo "$output" | jq -r 'has("applied")')" = "false" ]
}

# --- app scope --------------------------------------------------------------

@test "(global-cert:report) --global-cert-applied is true after applying the global cert" {
  install_fixture_cert
  create_app "$APP"
  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]

  run bash -c "dokku global-cert:report '$APP' --global-cert-applied 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "(global-cert:report) --global-cert-applied is false for an app with its own cert" {
  install_fixture_cert
  create_app "$APP"

  # give the app its own, independent certificate
  OWN="$(gc_fixture_dir)"
  make_self_signed_cert "$OWN" "own.example.com" "DNS:own.example.com"
  dokku certs:add "$APP" "${OWN}/server.crt" "${OWN}/server.key"

  run bash -c "dokku global-cert:report '$APP' --global-cert-applied 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "(global-cert:report) app report shows the applied status and cert info" {
  install_fixture_cert
  create_app "$APP"
  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]

  run dokku global-cert:report "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${APP} global-cert information"* ]]
  [[ "$output" == *"Global cert applied"* ]]
  [[ "$output" == *"true"* ]]
  [[ "$output" == *"global.example.com"* ]]
}

@test "(global-cert:report) app-scope --format json includes the applied key" {
  install_fixture_cert
  create_app "$APP"
  run dokku global-cert:apply "$APP"
  [ "$status" -eq 0 ]

  run bash -c "dokku global-cert:report '$APP' --format json 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.applied')" = "true" ]
  [ "$(echo "$output" | jq -r '.enabled')" = "true" ]
}
