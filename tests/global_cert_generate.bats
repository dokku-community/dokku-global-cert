#!/usr/bin/env bats

load 'test_helper'

setup() {
  reset_global_cert
}

teardown() {
  reset_global_cert
}

@test "(global-cert:generate) creates a self-signed cert, csr and key" {
  run gc_generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing certificate and key"* ]]

  $SUDO test -f "$(global_cert_crt)"
  $SUDO test -f "$(global_cert_key)"
  $SUDO test -f "$(global_cert_csr)"

  run global_cert_enabled
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "(global-cert:generate) prints the certificate signing request" {
  run gc_generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN CERTIFICATE REQUEST"* ]]
}

@test "(global-cert:generate) installs the key with restricted permissions" {
  run gc_generate
  [ "$status" -eq 0 ]
  # the key is chmod 640 by the plugin
  local kperms
  kperms="$($SUDO stat -c '%a' "$(global_cert_key)")"
  [ "$kperms" = "640" ]
}

@test "(global-cert:generate) is a no-op when a global cert already exists" {
  gc_generate
  run gc_generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global SSL endpoint already defined"* ]]
}
