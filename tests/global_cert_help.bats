#!/usr/bin/env bats

load 'test_helper'

@test "(global-cert) dokku global-cert prints the plugin help" {
  run dokku global-cert
  [ "$status" -eq 0 ]
  [[ "$output" == *"global-cert"* ]]
  for subcommand in add apply generate remove report set show update; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:help) lists every subcommand" {
  run dokku global-cert:help
  [ "$status" -eq 0 ]
  for subcommand in add apply generate remove report set show update; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:default) aliases the help output" {
  run dokku global-cert:default
  [ "$status" -eq 0 ]
  for subcommand in add apply generate remove report set show update; do
    [[ "$output" == *"global-cert:${subcommand}"* ]]
  done
}

@test "(global-cert:help apply) prints per-subcommand usage" {
  run dokku global-cert:help apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:apply"* ]]
  # the #A argument annotation renders as an arguments section
  [[ "$output" == *"app"* ]]
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

@test "(global-cert:help show) prints per-subcommand usage" {
  run dokku global-cert:help show
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:show"* ]]
  # the #A argument annotation renders as an arguments section
  [[ "$output" == *"key-type"* ]]
}

@test "(global-cert:help add) prints per-subcommand usage" {
  run dokku global-cert:help add
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:add"* ]]
}

@test "(global-cert:help update) prints per-subcommand usage" {
  run dokku global-cert:help update
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:update"* ]]
}

@test "(global-cert:help remove) prints per-subcommand usage" {
  run dokku global-cert:help remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"global-cert:remove"* ]]
}

@test "(global-cert:help set) renders the --force flag" {
  run dokku global-cert:help set
  [ "$status" -eq 0 ]
  # the #F annotation renders --force in a flags section
  [[ "$output" == *"--force"* ]]
}

@test "(global-cert:help) an unknown subcommand exits non-zero" {
  run dokku global-cert:help bogus-subcommand
  [ "$status" -ne 0 ]
}
