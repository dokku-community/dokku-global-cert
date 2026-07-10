#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  SRC=""
  OUT=""
}

teardown() {
  reset_global_cert
  [ -n "${SRC:-}" ] && rm -rf "$SRC"
  [ -n "${OUT:-}" ] && rm -rf "$OUT"
  return 0
}

# Install a deterministic global cert so the streamed PEM is stable.
install_fixture_cert() {
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com" "DNS:global.example.com"
  dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
}

# --- crt / key ---------------------------------------------------------------

@test "(global-cert:show) crt streams the stored certificate" {
  install_fixture_cert
  run dokku global-cert:show crt
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN CERTIFICATE"* ]]
  [ "$output" = "$($SUDO cat "$(global_cert_crt)")" ]
}

@test "(global-cert:show) key streams the stored private key" {
  install_fixture_cert
  run dokku global-cert:show key
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRIVATE KEY"* ]]
  [ "$output" = "$($SUDO cat "$(global_cert_key)")" ]
}

@test "(global-cert:show) crt/key can be exported and re-imported" {
  install_fixture_cert
  OUT="$(gc_fixture_dir)"
  bash -c "dokku global-cert:show crt > '${OUT}/server.crt'"
  bash -c "dokku global-cert:show key > '${OUT}/server.key'"
  chmod 644 "${OUT}/server.crt" "${OUT}/server.key"

  reset_global_cert
  run global_cert_enabled
  [ "$output" = "false" ]

  run dokku global-cert:set "${OUT}/server.crt" "${OUT}/server.key"
  [ "$status" -eq 0 ]
  run global_cert_enabled
  [ "$output" = "true" ]
}

# --- validation --------------------------------------------------------------

@test "(global-cert:show) fails without a type argument" {
  install_fixture_cert
  run dokku global-cert:show
  [ "$status" -ne 0 ]
  [[ "$output" == *"specify 'crt', 'key', or 'csr'"* ]]
}

@test "(global-cert:show) rejects an invalid type argument" {
  install_fixture_cert
  run dokku global-cert:show pem
  [ "$status" -ne 0 ]
  [[ "$output" == *"specify 'crt', 'key', or 'csr'"* ]]
}

@test "(global-cert:show) fails when no global cert is defined" {
  run dokku global-cert:show crt
  [ "$status" -ne 0 ]
  [[ "$output" == *"A global SSL endpoint is not defined"* ]]
}

# --- csr ---------------------------------------------------------------------

@test "(global-cert:show) csr streams the generated signing request" {
  gc_generate
  run dokku global-cert:show csr
  [ "$status" -eq 0 ]
  [[ "$output" == *"CERTIFICATE REQUEST"* ]]
  [ "$output" = "$($SUDO cat "$(global_cert_csr)")" ]
}

@test "(global-cert:show) csr fails when no signing request exists" {
  install_fixture_cert
  run dokku global-cert:show csr
  [ "$status" -ne 0 ]
  [[ "$output" == *"A global certificate signing request is not defined"* ]]
}
