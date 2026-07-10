#!/usr/bin/env bats

load 'test_helper'

@test "(global-cert) dokku global-cert prints the plugin help" {
  run dokku global-cert
  [ "$status" -eq 0 ]
  [[ "$output" == *"global-cert"* ]]
  for subcommand in generate remove report set; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:help) lists every subcommand" {
  run dokku global-cert:help
  [ "$status" -eq 0 ]
  for subcommand in generate remove report set; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:default) aliases the help output" {
  run dokku global-cert:default
  [ "$status" -eq 0 ]
  for subcommand in generate remove report set; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:help set) prints per-subcommand usage" {
  run dokku global-cert:help set
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:set"* ]]
  # the #A argument annotations render as an arguments section
  [[ "$output" == *"crt-file"* ]]
  [[ "$output" == *"key-file"* ]]
}

@test "(global-cert:help report) prints the report flags" {
  run dokku global-cert:help report
  [ "$status" -eq 0 ]
  [[ "$output" == *"global-cert:report"* ]]
  [[ "$output" == *"--global-cert-enabled"* ]]
}

@test "(global-cert:help generate) prints the generate example" {
  run dokku global-cert:help generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"global-cert:generate"* ]]
}
