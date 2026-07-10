#!/usr/bin/env bash
# Run inside the dokku container. Installs the plugin from the bind-mounted
# /plugin-src tree.
set -euo pipefail

PLUGIN_SRC="${PLUGIN_SRC:-/plugin-src}"

log() { echo "-----> $*"; }

if dokku plugin:installed global-cert; then
  log "global-cert plugin already installed; uninstalling first"
  dokku plugin:uninstall global-cert
fi

# `dokku plugin:install` derives the destination directory name from the
# basename of the source URL, so stage the bind-mounted source at a path
# whose basename is `global-cert` before installing.
log "Staging plugin source at /tmp/global-cert"
rm -rf /tmp/global-cert
cp -r "${PLUGIN_SRC}" /tmp/global-cert
# the repo's tmp/ scratch dir (compose-mode host state) must not ship inside the plugin
rm -rf /tmp/global-cert/tmp

# `dokku plugin:install` git-clones the URL, which would install committed
# HEAD rather than the working tree. Re-init the staged copy as a fresh
# single-commit repo so local uncommitted changes are exercised too.
rm -rf /tmp/global-cert/.git
(
  cd /tmp/global-cert
  git init --quiet
  git add -A
  git -c user.name=gctest -c user.email=gctest@dokku.test commit --quiet --message "test snapshot"
)

log "Installing global-cert plugin from /tmp/global-cert"
dokku plugin:install "file:///tmp/global-cert"

log "Setup complete"
