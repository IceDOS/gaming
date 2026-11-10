#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix nix-prefetch-git

# shellcheck disable=SC2034
NAME="eglantine"
# shellcheck disable=SC2034
REPO="Djihads80/Eglantine"
# shellcheck source=/dev/null
. "$(dirname "$0")/../update-common.sh"
