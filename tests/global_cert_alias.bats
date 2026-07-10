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

# global-cert:add and global-cert:update are aliases for global-cert:set and
# share its implementation, so they accept both file-path and tar-on-stdin imports.

@test "(global-cert:add) imports a cert and key from file paths" {
  run dokku global-cert:add "${SRC}/server.crt" "${SRC}/server.key"
  [ "$status" -eq 0 ]
  $SUDO test -f "$(global_cert_crt)"
  $SUDO test -f "$(global_cert_key)"
  run global_cert_enabled
  [ "$output" = "true" ]
}

@test "(global-cert:update) imports a cert and key from file paths" {
  run dokku global-cert:update "${SRC}/server.crt" "${SRC}/server.key"
  [ "$status" -eq 0 ]
  $SUDO test -f "$(global_cert_crt)"
  $SUDO test -f "$(global_cert_key)"
  run global_cert_enabled
  [ "$output" = "true" ]
}

# The tar-on-stdin path is where the shared function sets a RETURN trap; exercise
# it through the alias to confirm the import (and its cleanup) still works.
@test "(global-cert:add) imports a cert and key from a tarball on stdin" {
  local stage="${BATS_TEST_TMPDIR}/good"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "${SRC}/server.key" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/good.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:add <"$tarball"
  [ "$status" -eq 0 ]
  run global_cert_enabled
  [ "$output" = "true" ]
}

@test "(global-cert:update) imports a cert and key from a tarball on stdin" {
  local stage="${BATS_TEST_TMPDIR}/good"
  mkdir -p "$stage"
  cp "${SRC}/server.crt" "${SRC}/server.key" "$stage/"
  local tarball="${BATS_TEST_TMPDIR}/good.tar"
  make_cert_tarball "$tarball" "$stage"

  run dokku global-cert:update <"$tarball"
  [ "$status" -eq 0 ]
  run global_cert_enabled
  [ "$output" = "true" ]
}
