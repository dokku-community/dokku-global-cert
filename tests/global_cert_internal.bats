#!/usr/bin/env bats

# White-box unit tests that source internal-functions directly (via
# run_internal_fn) to reach branches that are impossible or non-deterministic to
# assert through the CLI in a single run. The clearest example is the
# certs-set-trigger vs certs:add fallback: which path runs is fixed by the
# installed dokku version, so no black-box test can assert both branches at
# once; overriding PLUGIN_ENABLED_PATH with a controlled sandbox can.

load 'test_helper'

setup() {
  FIXTURES=()
}

teardown() {
  local f
  for f in "${FIXTURES[@]}"; do
    [ -n "$f" ] && rm -rf "$f"
  done
  return 0
}

# --- fn-global-cert-certs-set-available -------------------------------------

@test "(fn-global-cert-certs-set-available) returns 0 when an enabled plugin ships an executable certs-set" {
  local enabled
  enabled="$(make_certs_set_sandbox with-trigger)"
  FIXTURES+=("$enabled")

  run run_internal_fn ENABLED_PATH="$enabled" fn-global-cert-certs-set-available
  [ "$status" -eq 0 ]
}

@test "(fn-global-cert-certs-set-available) returns 1 when no enabled plugin ships certs-set" {
  local enabled
  enabled="$(make_certs_set_sandbox)"
  FIXTURES+=("$enabled")

  run run_internal_fn ENABLED_PATH="$enabled" fn-global-cert-certs-set-available
  [ "$status" -eq 1 ]
}

# --- fn-get-ssl-hostnames ---------------------------------------------------

@test "(fn-get-ssl-hostnames) returns the CN for a CN-only cert" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "cn-only.example.com"

  # a cert with only a CN and no SAN reports its CN. The subject is normalized
  # with -nameopt RFC2253 so the CN is extracted regardless of the OpenSSL
  # version's subject formatting (legacy "/CN=" vs OpenSSL 3.x "CN = ").
  run run_internal_fn fn-get-ssl-hostnames "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "cn-only.example.com" ]
}

@test "(fn-get-ssl-hostnames) returns the SAN entries sorted and de-duplicated" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  # SANs are intentionally out of order and contain a duplicate to exercise the
  # sort -u at the end of the function
  make_self_signed_cert "$dir" "a.example.com" \
    "DNS:b.example.com,DNS:a.example.com,DNS:b.example.com,DNS:c.example.com"

  run run_internal_fn fn-get-ssl-hostnames "$dir"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "a.example.com" ]
  [ "${lines[1]}" = "b.example.com" ]
  [ "${lines[2]}" = "c.example.com" ]
}

# --- fn-global-cert-fingerprint ---------------------------------------------

@test "(fn-global-cert-fingerprint) prints the sha256 fingerprint of a readable cert" {
  local dir expected
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "fp.example.com"
  expected="$(openssl x509 -noout -fingerprint -sha256 -in "${dir}/server.crt")"

  run run_internal_fn fn-global-cert-fingerprint "${dir}/server.crt"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "(fn-global-cert-fingerprint) prints nothing and exits 0 for a missing file" {
  run run_internal_fn fn-global-cert-fingerprint "/tmp/gc-missing-$$-does-not-exist.crt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "(fn-global-cert-fingerprint) prints nothing for a non-certificate file" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  printf 'not a certificate\n' >"${dir}/notcert.txt"
  chmod 644 "${dir}/notcert.txt"

  run run_internal_fn fn-global-cert-fingerprint "${dir}/notcert.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- fn-is-ssl-enabled ------------------------------------------------------

@test "(fn-is-ssl-enabled) returns 1 when only the crt is present" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "partial.example.com"
  rm -f "${dir}/server.key"

  run run_internal_fn fn-is-ssl-enabled "$dir"
  [ "$status" -eq 1 ]
}

@test "(fn-is-ssl-enabled) returns 1 when only the key is present" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "partial.example.com"
  rm -f "${dir}/server.crt"

  run run_internal_fn fn-is-ssl-enabled "$dir"
  [ "$status" -eq 1 ]
}

# --- fn-is-file-import ------------------------------------------------------

@test "(fn-is-file-import) returns 0 when both crt and key files exist" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "fi.example.com"

  run run_internal_fn fn-is-file-import "${dir}/server.crt" "${dir}/server.key"
  [ "$status" -eq 0 ]
}

@test "(fn-is-file-import) returns 1 when only the crt path is supplied" {
  local dir
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "fi.example.com"

  run run_internal_fn fn-is-file-import "${dir}/server.crt" ""
  [ "$status" -eq 1 ]
}
