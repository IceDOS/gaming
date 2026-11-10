#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix nix-prefetch-git

# shellcheck disable=SC2034
NAME="lichii"
# shellcheck disable=SC2034
REPO="zortos293/Lichii"
# shellcheck source=/dev/null
. "$(dirname "$0")/../update-common.sh"
