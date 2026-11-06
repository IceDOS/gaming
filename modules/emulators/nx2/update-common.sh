# Updater for AppImage builds of the nx2 emulators. Each module's update.sh sets
# NAME and REPO, then sources this file.

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

main() {
  banner "$NAME updater"

  # Every upstream release is a prerelease, so gh_latest_release finds none.
  # The tag filter also skips `v*` candidates, `branch-*` test builds and old `nx2-build-*` tags.
  info "Finding latest $REPO build..."
  local tag
  tag=$(gh_api "https://api.github.com/repos/$REPO/releases?per_page=100" \
    | jq -r '[.[] | select(.draft | not) | select(.tag_name | test("^build-[0-9]+$"))]
             | max_by(.tag_name | ltrimstr("build-") | tonumber) | .tag_name // ""')
  [ -n "$tag" ] || error "no build-* release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  local version="${tag#build-}"
  # Prefer the PGO AppImage; some builds ship only the plain one.
  local url
  url=$(gh_api "https://api.github.com/repos/$REPO/releases/tags/$tag" \
    | jq -r --arg n "$NAME" '[.assets[] | select(.name == "\($n)-linux-x86_64-pgo.AppImage" or .name == "\($n)-linux-x86_64.AppImage")]
             | sort_by(.name | test("-pgo") | not) | .[0].browser_download_url // ""')
  [ -n "$url" ] || error "no x86_64 AppImage in $tag"
  info "  Asset: ${url##*/}"

  info "  Hashing AppImage..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty "$NAME" "$version" "$url" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$tag" --arg url "$url" --arg hash "$hash" \
    '{version: $version, rev: $rev, url: $url, hash: $hash}' \
    | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
