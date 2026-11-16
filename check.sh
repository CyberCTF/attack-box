#!/usr/bin/env bash
# The attack box's check, the command CI runs (.github/workflows/image.yml) and a contributor runs:
#
#   ./check.sh            the scripts: the VM set-up's compositions parse, shellcheck passes
#   ./check.sh image      the image built locally (no registry, no secrets) and smoke-tested
#   ./check.sh all        both
#
# The VM set-up's parts are fragments of one script (vm/kali.sh defines `$keep`): each composition
# the launcher makes must parse, with the player's account between the toolset and the desktop.
set -euo pipefail
cd "$(dirname "$0")"

scripts() {
  local parts
  for parts in "vm/kali.sh vm/toolset.sh" "vm/kali.sh vm/toolset.sh vm/desktop.sh" "vm/kali.sh vm/desktop.sh"; do
    # shellcheck disable=SC2086 # the list is the files, split on purpose
    if ! cat $parts | sh -n; then echo "check: the VM set-up doesn't parse as $parts" >&2; return 1; fi
  done
  shellcheck check.sh player-account.sh smoke-test.sh
  echo "check: scripts ok"
}

image() {
  docker build --pull -t attack-box:smoke .
  ./smoke-test.sh attack-box:smoke
  echo "check: image ok"
}

case "${1:-scripts}" in
  scripts) scripts ;;
  image) image ;;
  all) scripts && image ;;
  *) echo "usage: ./check.sh [scripts|image|all]" >&2; exit 2 ;;
esac
