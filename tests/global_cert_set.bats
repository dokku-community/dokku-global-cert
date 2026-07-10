#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
  SRC="$(gc_fixture_dir)"
  make_self_signed_cert "$SRC" "global.example.com"
}

teardown() {
  reset_global_cert
  rm -rf "$SRC"
}

# --- file import ------------------------------------------------------------

@test "(global-cert:set) imports a cert and key from file paths" {
  run dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
  [ "$status" -eq 0 ]
  $SUDO test -f "$(global_cert_crt)"
  $SUDO test -f "$(global_cert_key)"
  run global_cert_enabled
  [ "$output" = "true" ]
}

@test "(global-cert:set) installs the imported key with restricted permissions" {
  run dokku global-cert:set "${SRC}/server.crt" "${SRC}/server.key"
  [ "$status" -eq 0 ]
  local kperms
  kperms="$($SUDO stat -c '%a' "$(global_cert_key)")"
  [ "$kperms" = "640" ]
}

@test "(global-cert:set) fails when the crt file does not exist" {
  run dokku global-cert:set "${BATS_TEST_TMPDIR}/missing.crt" "${SRC}/server.key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRT file specified not found"* ]]
}

@test "(global-cert:set) fails when the key file does not exist" {
  run dokku global-cert:set "${SRC}/server.crt" "${BATS_TEST_TMPDIR}/missing.key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"KEY file specified not found"* ]]
}

# --- tar-on-stdin import ----------------------------------------------------

@test "(global-cert:set) imports a cert and key from a tarball on stdin" {
  local stage="${BATS_TEST_TMPDIR}/good"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "${SRC}/server.key" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/good.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:set <"$tarball"
  [ "$status" -eq 0 ]
  $SUDO test -f "$(global_cert_crt)"
  $SUDO test -f "$(global_cert_key)"
  run global_cert_enabled
  [ "$output" = "true" ]
}

@test "(global-cert:set) handles a tarball whose cert is nested in a subdirectory" {
  local stage="${BATS_TEST_TMPDIR}/nested/certs"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "${SRC}/server.key" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/nested.tar"
  make_cert_tarball "$tarball" "${BATS_TEST_TMPDIR}/nested"

  run dokku global-cert:set <"$tarball"
  [ "$status" -eq 0 ]
  run global_cert_enabled
  [ "$output" = "true" ]
}

@test "(global-cert:set) fails when the tarball has no crt file" {
  local stage="${BATS_TEST_TMPDIR}/nocrt"
  mkdir -p "$stage"
  cp "${SRC}/server.key" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/nocrt.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:set <"$tarball"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tar archive is missing .crt file"* ]]
}

@test "(global-cert:set) fails when the tarball has no key file" {
  local stage="${BATS_TEST_TMPDIR}/nokey"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/nokey.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:set <"$tarball"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tar archive is missing .key file"* ]]
}

@test "(global-cert:set) fails when the tarball has more than one crt file" {
  local stage="${BATS_TEST_TMPDIR}/twocrt"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "$stage/server.crt"
  cp "${SRC}/server.crt" "$stage/extra.crt"
  cp "${SRC}/server.key" "$stage/server.key"
  local tarball="${BATS_TEST_TMPDIR}/twocrt.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:set <"$tarball"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tar archive contains more than one .crt file"* ]]
}

@test "(global-cert:set) fails when the tarball has more than one key file" {
  local stage="${BATS_TEST_TMPDIR}/twokey"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "$stage/server.crt"
  cp "${SRC}/server.key" "$stage/server.key"
  cp "${SRC}/server.key" "$stage/extra.key"
  local tarball="${BATS_TEST_TMPDIR}/twokey.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:set <"$tarball"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tar archive contains more than one .key file"* ]]
}
