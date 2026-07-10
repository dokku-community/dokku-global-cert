#!/usr/bin/env bash
# Helpers for the dokku-global-cert bats suite. Sourced by every *.bats file.

# `SUDO` is empty in compose mode (bats already runs as root in the dokku
# container) and `sudo` in native mode (files under /var/lib/dokku need
# elevation to read or modify).
SUDO="${SUDO:-}"

new_app_name() {
  echo "gctest-${BATS_TEST_NUMBER:-0}-$(date +%s)-${RANDOM}"
}

create_app() {
  local app="$1"
  dokku apps:create "$app"
}

cleanup_app() {
  local app="$1"
  if dokku apps:exists "$app" >/dev/null 2>&1; then
    dokku --force apps:destroy "$app" >/dev/null 2>&1 || true
  fi
}

# The global certificate lives under DOKKU_LIB_ROOT/config/global-cert.
global_cert_root() {
  echo "/var/lib/dokku/config/global-cert"
}

global_cert_crt() { echo "$(global_cert_root)/server.crt"; }
global_cert_key() { echo "$(global_cert_root)/server.key"; }
global_cert_csr() { echo "$(global_cert_root)/server.csr"; }

# Path to an app's imported TLS certificate, written by `dokku certs:add` when
# the post-create / post-app-clone hooks apply the global cert.
app_tls_crt() { echo "/home/dokku/$1/tls/server.crt"; }

# Remove any installed global certificate so cert-mutating tests don't leak
# state across files or tests. Safe to call when nothing is installed.
reset_global_cert() {
  $SUDO rm -f "$(global_cert_crt)" "$(global_cert_key)" "$(global_cert_csr)"
}

# Value of a single global-scope report info flag, with openssl's verify chatter
# suppressed. `global-cert:report` builds its full flag map up front, so `openssl
# verify` on a self-signed cert prints "self-signed certificate" warnings to
# stderr even when an unrelated flag is requested; drop stderr so callers see just
# the value. A bare info flag now reports per-app, so `--global` selects the global
# certificate scope these helpers assert against.
global_cert_report_value() {
  dokku global-cert:report --global "$1" 2>/dev/null
}

# Report the plugin's view of whether a global cert is installed.
global_cert_enabled() {
  global_cert_report_value --global-cert-enabled
}

# Run global-cert:generate non-interactively. `openssl req -new` has no
# -subj/-batch, so it reads the DN from stdin; feed blank lines to accept the
# openssl.cnf defaults for every prompt (country, state, ..., challenge
# password, company name).
gc_generate() {
  printf '\n\n\n\n\n\n\n\n\n\n' | dokku global-cert:generate
}

# Create a world-traversable fixture directory under /tmp and echo its path.
# BATS_TEST_TMPDIR and its ancestors are not traversable by the dokku user that
# `dokku ...` runs as, so file-path arguments (as opposed to stdin redirects,
# whose fd is opened by the root test shell) must point somewhere the dokku user
# can reach. Callers should `rm -rf` the returned path in teardown.
gc_fixture_dir() {
  local dir
  dir="$(mktemp -d /tmp/gc-fixture.XXXXXX)"
  chmod 755 "$dir"
  echo "$dir"
}

# Generate a deterministic self-signed cert/key pair into <dir> for the set/
# report fixtures. <cn> sets the CN; the optional <san> is an openssl
# subjectAltName value, e.g. "DNS:global.example.com,DNS:www.example.com".
# Files are made world-readable so `dokku ...` can read them in native mode
# where the plugin's cp runs as the dokku user.
make_self_signed_cert() {
  local dir="$1" cn="$2" san="${3:-}"
  mkdir -p "$dir"
  chmod 755 "$dir"
  if [ -n "$san" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
      -subj "/CN=${cn}" -addext "subjectAltName=${san}" \
      -keyout "${dir}/server.key" -out "${dir}/server.crt" >/dev/null 2>&1
  else
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
      -subj "/CN=${cn}" \
      -keyout "${dir}/server.key" -out "${dir}/server.crt" >/dev/null 2>&1
  fi
  chmod 644 "${dir}/server.crt" "${dir}/server.key"
}

# Build a tarball at $1 from the contents of directory $2 (entries are stored
# relative to that dir). Used by the tar-on-stdin import tests.
make_cert_tarball() {
  local tarball="$1" dir="$2"
  tar -cf "$tarball" -C "$dir" .
}

# The bats suite never deploys, so lifecycle triggers are invoked directly. The
# dokku CLI normally exports the plugin environment; the bats shell does not, so
# set it here. Paths are the standard install layout, identical in compose and
# native modes. The plugin's own trigger scripts are run (rather than
# `plugn trigger`, which fans out to every plugin) to keep each assertion scoped
# to global-cert. Leading NAME=VALUE arguments override the defaults (env
# applies later assignments last), which the install/uninstall tests use to
# sandbox DOKKU_LIB_ROOT.
dokku_plugin_env() {
  $SUDO env \
    DOKKU_ROOT=/home/dokku \
    DOKKU_LIB_ROOT=/var/lib/dokku \
    PLUGIN_PATH=/var/lib/dokku/plugins \
    PLUGIN_AVAILABLE_PATH=/var/lib/dokku/plugins/available \
    PLUGIN_ENABLED_PATH=/var/lib/dokku/plugins/enabled \
    PLUGIN_CORE_PATH=/var/lib/dokku/core-plugins \
    PLUGIN_CORE_AVAILABLE_PATH=/var/lib/dokku/core-plugins/available \
    "$@"
}

# Absolute path to an installed plugin trigger/subcommand script.
plugin_script() {
  echo "/var/lib/dokku/plugins/available/global-cert/$1"
}

# Create an isolated DOKKU_LIB_ROOT under the test's tmpdir and echo its path.
# Triggers fired with DOKKU_LIB_ROOT pointed here mutate a throwaway config
# root instead of the real plugin install.
sandbox_lib_root() {
  local root="${BATS_TEST_TMPDIR}/libroot-${RANDOM}"
  mkdir -p "${root}"
  echo "${root}"
}

# Remove the sandbox trees created by sandbox_lib_root. Triggers fired through
# $SUDO (native mode) leave root-owned files under them, which bats' own
# non-root cleanup at the end of the run cannot remove; delete them with $SUDO
# in teardown so the run's final cleanup succeeds. Call from the teardown of any
# file that uses sandbox_lib_root.
cleanup_sandboxes() {
  $SUDO rm -rf "${BATS_TEST_TMPDIR}"/libroot-* 2>/dev/null || true
}

# Run a plugin trigger/subcommand script directly (see dokku_plugin_env). The
# first argument is the script name under the installed plugin dir; the rest are
# passed through to it. Prefix with `LIB_ROOT=<dir>` to sandbox DOKKU_LIB_ROOT
# so filesystem side effects land in a throwaway tree.
fire_trigger() {
  local lib_override=()
  if [[ "$1" == LIB_ROOT=* ]]; then
    lib_override=(DOKKU_LIB_ROOT="${1#LIB_ROOT=}")
    shift
  fi
  local script="$1"
  shift
  dokku_plugin_env "${lib_override[@]}" "$(plugin_script "$script")" "$@"
}

# --- certificate assertions -------------------------------------------------
# The plugin's notion of "the app serves the global cert" is a sha256
# fingerprint match between the app's leaf cert and the global one (see
# fn-global-cert-applied). These helpers assert that directly instead of
# grepping `dokku certs:report` text, so a byte-level cert swap is caught.

# sha256 fingerprint of an app's imported cert / of the global cert. Empty when
# the file is missing or unreadable (mirrors fn-global-cert-fingerprint).
app_cert_fingerprint() { $SUDO openssl x509 -noout -fingerprint -sha256 -in "$(app_tls_crt "$1")" 2>/dev/null; }
global_cert_fingerprint() { $SUDO openssl x509 -noout -fingerprint -sha256 -in "$(global_cert_crt)" 2>/dev/null; }

# Assert an app currently serves the exact global certificate.
assert_app_serves_global_cert() {
  local app="$1" app_fp global_fp
  app_fp="$(app_cert_fingerprint "$app")"
  global_fp="$(global_cert_fingerprint)"
  if [[ -z "$app_fp" ]]; then
    echo "expected app $app to serve the global cert, but it has no readable cert" >&2
    return 1
  fi
  if [[ "$app_fp" != "$global_fp" ]]; then
    echo "app $app cert ($app_fp) does not match the global cert ($global_fp)" >&2
    return 1
  fi
}

# Assert an app has a cert whose fingerprint differs from the global one (i.e.
# its own, independent cert).
refute_app_serves_global_cert() {
  local app="$1" app_fp global_fp
  app_fp="$(app_cert_fingerprint "$app")"
  global_fp="$(global_cert_fingerprint)"
  if [[ -z "$app_fp" ]]; then
    echo "expected app $app to have its own cert, but it has none" >&2
    return 1
  fi
  if [[ "$app_fp" == "$global_fp" ]]; then
    echo "expected app $app not to serve the global cert, but it does ($app_fp)" >&2
    return 1
  fi
}

# openssl accessors for an app's imported cert, ported from dokku-letsencrypt's
# cert_subject/cert_issuer/cert_san helpers.
app_cert_subject() { $SUDO openssl x509 -in "$(app_tls_crt "$1")" -noout -subject 2>/dev/null; }
app_cert_issuer() { $SUDO openssl x509 -in "$(app_tls_crt "$1")" -noout -issuer 2>/dev/null; }
app_cert_san() {
  $SUDO openssl x509 -in "$(app_tls_crt "$1")" -noout -text 2>/dev/null |
    grep --after-context=1 'Subject Alternative Name' | tail -n 1 | xargs
}

# Assert the app cert's SAN list contains <needle>.
assert_app_cert_san_contains() {
  local app="$1" needle="$2"
  app_cert_san "$app" | grep -qF "$needle"
}

# Thin wrappers over the repeated `$SUDO test -f` on an app's TLS cert.
assert_app_has_cert() { $SUDO test -f "$(app_tls_crt "$1")"; }
refute_app_has_cert() { $SUDO test ! -f "$(app_tls_crt "$1")"; }

# --- internal-function unit-test plumbing -----------------------------------
# Source the installed internal-functions and run a single function under the
# plugin environment, capturing status/output the way bats' `run` expects.
# Leading `ENABLED_PATH=<dir>` / `LIB_ROOT=<dir>` override PLUGIN_ENABLED_PATH /
# DOKKU_LIB_ROOT so version-fixed branches (certs-set vs certs:add) and config
# roots can be driven deterministically. `set +e` is re-enabled after sourcing
# because internal-functions sets `set -eo pipefail`, which would otherwise
# abort the shell (and lose $status) on any function that returns non-zero.
run_internal_fn() {
  local env_overrides=()
  while [[ "${1:-}" == ENABLED_PATH=* || "${1:-}" == LIB_ROOT=* ]]; do
    case "$1" in
      ENABLED_PATH=*) env_overrides+=(PLUGIN_ENABLED_PATH="${1#ENABLED_PATH=}") ;;
      LIB_ROOT=*) env_overrides+=(DOKKU_LIB_ROOT="${1#LIB_ROOT=}") ;;
    esac
    shift
  done
  # the $1/$@ inside the single-quoted script are expanded by the inner bash -c,
  # not the current shell, which is exactly what we want here
  # shellcheck disable=SC2016
  dokku_plugin_env "${env_overrides[@]}" bash -c '
    source "$1"
    set +e
    shift
    "$@"
  ' _ "$(plugin_script internal-functions)" "$@"
}

# Create a throwaway enabled-plugins tree and echo its path. With any argument,
# it ships an executable `somepkg/certs-set` so fn-global-cert-certs-set-available
# detects the trigger; without one, the tree is empty (the certs:add fallback).
# The returned path is world-traversable; callers should `rm -rf` it in teardown.
make_certs_set_sandbox() {
  local with_trigger="${1:-}" root
  root="$(mktemp -d /tmp/gc-enabled.XXXXXX)"
  chmod 755 "$root"
  if [[ -n "$with_trigger" ]]; then
    mkdir -p "$root/somepkg"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$root/somepkg/certs-set"
    chmod +x "$root/somepkg/certs-set"
  fi
  echo "$root"
}
