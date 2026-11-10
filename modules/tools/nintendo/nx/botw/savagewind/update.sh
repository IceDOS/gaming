#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CORE="${ICEDOS_CORE:-$REPO_ROOT/.icedos-core}"
[ -d "$CORE" ] || CORE="$REPO_ROOT/../core"
[ -f "$CORE/lib/update-lib.sh" ] || {
  echo "ERROR: core not found; set ICEDOS_CORE=/path/to/IceDOS/core" >&2
  exit 1
}
# shellcheck source=/dev/null
. "$CORE/lib/update-lib.sh"

PIN="$SCRIPT_DIR/source.json"
REPO="Revivedx/SavageWindRecomp"

main() {
  banner "savagewind updater"

  info "Finding latest $REPO release..."
  local tag
  tag=$(gh_api "https://api.github.com/repos/$REPO/releases?per_page=30" \
    | jq -r '[.[] | select(.draft | not)] | first | .tag_name // ""')
  [ -n "$tag" ] || error "no release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  local version="${tag#v}"
  local url="https://github.com/$REPO/releases/download/$tag/Savage_Wind-$version-x86_64.AppImage"

  info "  Hashing AppImage..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty "savagewind" "$version" "$url" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$tag" --arg url "$url" --arg hash "$hash" \
    '{version: $version, rev: $rev, url: $url, hash: $hash}' \
    | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
