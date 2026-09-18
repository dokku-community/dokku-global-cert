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

# --- fn-global-cert-format-hex-field ----------------------------------------
# The label openssl prints before the "=" varies by version (3.x "sha256",
# 1.x/LibreSSL "SHA256"), so the formatter cuts at the separator rather than
# matching a literal. These cases are the bash port of core's TestFormatSSLHexField.

@test "(fn-global-cert-format-hex-field) strips the OpenSSL 1.x fingerprint label" {
  run run_internal_fn fn-global-cert-format-hex-field "SHA256 Fingerprint=B7:DF:D5:84:C6:2E:27:BF"
  [ "$status" -eq 0 ]
  [ "$output" = "B7:DF:D5:84:C6:2E:27:BF" ]
}

@test "(fn-global-cert-format-hex-field) strips the OpenSSL 3.x fingerprint label" {
  run run_internal_fn fn-global-cert-format-hex-field "sha256 Fingerprint=B7:DF:D5:84:C6:2E:27:BF"
  [ "$status" -eq 0 ]
  [ "$output" = "B7:DF:D5:84:C6:2E:27:BF" ]
}

@test "(fn-global-cert-format-hex-field) uppercases a lowercase digest" {
  run run_internal_fn fn-global-cert-format-hex-field "sha256 Fingerprint=b7:df:d5:84:c6:2e:27:bf"
  [ "$status" -eq 0 ]
  [ "$output" = "B7:DF:D5:84:C6:2E:27:BF" ]
}

@test "(fn-global-cert-format-hex-field) returns a serial unchanged" {
  run run_internal_fn fn-global-cert-format-hex-field "serial=322844AD8CD6D4FF76B05C50833AB91DEEDA2AD1"
  [ "$status" -eq 0 ]
  [ "$output" = "322844AD8CD6D4FF76B05C50833AB91DEEDA2AD1" ]
}

@test "(fn-global-cert-format-hex-field) uppercases a lowercase serial" {
  run run_internal_fn fn-global-cert-format-hex-field "serial=c46823e5d7c09fc9"
  [ "$status" -eq 0 ]
  [ "$output" = "C46823E5D7C09FC9" ]
}

@test "(fn-global-cert-format-hex-field) preserves a negative serial" {
  run run_internal_fn fn-global-cert-format-hex-field "serial=-1F2E"
  [ "$status" -eq 0 ]
  [ "$output" = "-1F2E" ]
}

@test "(fn-global-cert-format-hex-field) trims surrounding whitespace" {
  run run_internal_fn fn-global-cert-format-hex-field "  serial=C46823E5D7C09FC9  "
  [ "$status" -eq 0 ]
  [ "$output" = "C46823E5D7C09FC9" ]
}

# The next two are the `set -e` guard: cmd-global-cert-report-single expands
# these helpers inside an array literal, where a non-zero status aborts the whole
# report with no output. A junk or empty line must yield "" and still exit 0.

@test "(fn-global-cert-format-hex-field) returns empty and exits 0 for a line with no separator" {
  run run_internal_fn fn-global-cert-format-hex-field "unable to load certificate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "(fn-global-cert-format-hex-field) returns empty and exits 0 for empty input" {
  run run_internal_fn fn-global-cert-format-hex-field ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- fn-global-cert-hex-field -----------------------------------------------

@test "(fn-global-cert-hex-field) prints the bare uppercase serial of a readable cert" {
  local dir expected
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "serial.example.com"
  expected="$(openssl x509 -noout -serial -in "${dir}/server.crt" | cut -d= -f2- | tr '[:lower:]' '[:upper:]')"

  run run_internal_fn fn-global-cert-hex-field "${dir}/server.crt" -serial
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  [[ "$output" != *"serial="* ]]
}

@test "(fn-global-cert-hex-field) prints nothing and exits 0 for a missing file" {
  run run_internal_fn fn-global-cert-hex-field "/tmp/gc-missing-$$-does-not-exist.crt" -serial
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- fn-global-cert-fingerprint ---------------------------------------------

@test "(fn-global-cert-fingerprint) prints the bare uppercase sha256 fingerprint of a readable cert" {
  local dir expected
  dir="$(gc_fixture_dir)"
  FIXTURES+=("$dir")
  make_self_signed_cert "$dir" "fp.example.com"
  # openssl prints "<label>=<hex>"; the function reports just the hex, so the
  # value is directly comparable to core's `certs:report --ssl-fingerprint`
  expected="$(openssl x509 -noout -fingerprint -sha256 -in "${dir}/server.crt" | cut -d= -f2- | tr '[:lower:]' '[:upper:]')"

  run run_internal_fn fn-global-cert-fingerprint "${dir}/server.crt"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  # pin the format: the openssl label must not leak into the value
  [[ "$output" != *"Fingerprint="* ]]
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
