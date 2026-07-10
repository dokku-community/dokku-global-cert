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

# Install a deterministic global cert (CN + two SANs) so hostname/subject/issuer
# assertions are stable.
install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com" "DNS:global.example.com,DNS:www.example.com"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

# --- no cert installed ------------------------------------------------------

@test "(global-cert:report) renders a full report" {
  run dokku global-cert:report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global SSL Information"* ]]
  [[ "$output" == *"Global cert dir"* ]]
  [[ "$output" == *"Global cert enabled"* ]]
  [[ "$output" == *"Global cert hostnames"* ]]
  [[ "$output" == *"Global cert issuer"* ]]
  [[ "$output" == *"Global cert subject"* ]]
  [[ "$output" == *"Global cert verified"* ]]
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
  run dokku global-cert:report --not-a-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid flag passed, valid flags:"* ]]
}

# --- cert installed ---------------------------------------------------------

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

@test "(global-cert:report) full report reflects an installed cert" {
  install_fixture_cert
  run dokku global-cert:report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global cert enabled"* ]]
  [[ "$output" == *"true"* ]]
  [[ "$output" == *"global.example.com"* ]]
}
